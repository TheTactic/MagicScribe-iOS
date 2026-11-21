import Foundation

/// Owns the continuous chunked-recording loop for real multi-minute
/// dictation — matching web's ~45-60s chunking cadence, not the demo's
/// single 15s utterance.
///
/// Deliberately SEQUENTIAL (record chunk → stop → await transcription →
/// apply → record next), not overlapped. This sidesteps out-of-order-chunk
/// risk entirely — with no concurrent in-flight chunks there's no ordering
/// problem to solve — at the cost of a brief pause between chunks during
/// each one's transcription round trip. A deliberate v1 simplification, not
/// an oversight.
///
/// A fresh `AudioRecorder` is used every iteration — concrete bug avoided:
/// reusing one shared instance across chunks races on its own
/// `recordingURL` ivar inside `discardRecording()`.
@MainActor
final class ContinuousDictationController {
    enum HaltReason {
        case userStopped
        case planLimitReached(String)
        case error(String)
    }

    private(set) var isActive = false

    let formattingState: DocFormattingState
    private let speechService: SpeechService
    private let docsService: DocsService
    private let chunkDuration: TimeInterval
    private let languageProvider: () -> String
    /// Only set during onboarding ("ios_onboarding_demo_docs") — bypasses
    /// the verified-email requirement server-side on both calls this loop
    /// makes (speech.php's transcribe, refine.php's correction pass). nil
    /// for every real app call, matching VoiceEditController's identical
    /// `context` parameter.
    private let demoContext: String?

    /// Bumped only by `cancel()` — a hard stop that abandons whatever's
    /// in-flight right now. Graceful `stop()` leaves this unchanged so the
    /// loop still finalizes and applies the chunk already in progress
    /// (the user's last few seconds of speech shouldn't just vanish).
    private var generation = 0
    private var currentRecorder: AudioRecorder?
    private var loopTask: Task<Void, Never>?

    /// Per-session state for the Claude refine pass — reset in `start()`,
    /// mirrors web's module-level `runningContext`/`lastChunkInserted`/
    /// `lastChunkEndedWithStop` (docs.js), which track only what's been
    /// dictated *this session*, not the document's pre-existing content.
    private var runningContext = ""
    private var lastChunkInserted = ""
    private var lastChunkEndedWithStop = false

    var onChunkApplied: ((AttributedString) -> Void)?
    /// Fired when Claude's refine pass finds a word split across a chunk
    /// boundary and corrects the *previous* chunk retroactively — the
    /// caller finds the last occurrence of the first string in its live
    /// text and replaces it with the second.
    var onPreviousChunkCorrected: ((String, String) -> Void)?
    var onHalted: ((HaltReason) -> Void)?
    var onUndoRequested: (() -> Void)?
    var onRedoRequested: (() -> Void)?

    init(
        formattingState: DocFormattingState,
        speechService: SpeechService? = nil,
        docsService: DocsService = DocsService(),
        chunkDuration: TimeInterval = 50,
        demoContext: String? = nil,
        language: @escaping () -> String
    ) {
        self.formattingState = formattingState
        // Constructed in the body, not as a default argument value — a
        // default argument expression evaluates in a context that doesn't
        // reliably inherit this MainActor-isolated init's isolation.
        self.speechService = speechService ?? SpeechService()
        self.docsService = docsService
        self.chunkDuration = chunkDuration
        self.demoContext = demoContext
        self.languageProvider = language
    }

    @discardableResult
    func start() async -> Bool {
        guard !isActive else { return true }
        guard await AudioRecorder().requestPermission() else { return false }
        isActive = true
        runningContext = ""
        lastChunkInserted = ""
        lastChunkEndedWithStop = false
        let myGeneration = generation
        loopTask = Task { [weak self] in
            await self?.recordLoop(generation: myGeneration)
        }
        return true
    }

    /// Finalizes whatever's currently recording so it still gets
    /// transcribed and applied, then ends the session once that chunk
    /// resolves.
    func stop() {
        guard isActive else { return }
        isActive = false
        currentRecorder?.stop()
    }

    /// Hard stop: abandon whatever's in flight right now, no final chunk.
    func cancel() {
        isActive = false
        generation += 1
        currentRecorder?.discardRecording()
        currentRecorder = nil
        loopTask?.cancel()
        loopTask = nil
    }

    private func recordLoop(generation myGeneration: Int) async {
        while generation == myGeneration {
            let recorder = AudioRecorder(maxDuration: chunkDuration)
            currentRecorder = recorder
            do {
                try recorder.start()
            } catch {
                isActive = false
                onHalted?(.error("Couldn't start recording — try again."))
                return
            }

            // Poll in short intervals rather than one long sleep, so an
            // external stop() (which calls recorder.stop() directly) is
            // noticed quickly instead of waiting out the full chunk.
            var waited: TimeInterval = 0
            let pollInterval: TimeInterval = 0.2
            while waited < chunkDuration && recorder.isRecording {
                try? await Task.sleep(for: .seconds(pollInterval))
                waited += pollInterval
            }
            guard generation == myGeneration else { return }

            guard let fileURL = recorder.stop() else {
                recorder.discardRecording()
                if !isActive { onHalted?(.userStopped) }
                return
            }

            do {
                let transcript = try await speechService.transcribe(
                    fileURL: fileURL, language: languageProvider(), context: demoContext ?? "docs"
                )
                recorder.discardRecording()
                guard generation == myGeneration else { return }

                // Discard Whisper hallucinations (silence filler, polite
                // sign-offs, etc.) — same as web's sendChunkToWhisper.
                // Most commonly a bare "." from the beat of near-silence
                // before the user starts speaking. Continue listening
                // rather than inserting or halting.
                if WhisperHallucinationFilter.isHallucination(transcript) {
                    if !isActive {
                        onHalted?(.userStopped)
                        return
                    }
                    continue
                }

                let tokens = MagicCommandParser.tokenize(transcript)
                let hasFormatting = tokens.contains {
                    if case .command = $0 { return true }
                    return false
                }

                let result: DocFormattingState.ChunkResult
                if hasFormatting {
                    // Any magic command in the chunk skips the refine pass
                    // entirely — faithful to web's own `hasFormatting`
                    // branch: refine.php takes one flat string, not a
                    // structured token sequence, so a formatted chunk is
                    // never a candidate for it on web either. Not a gap
                    // specific to this port.
                    result = formattingState.buildRuns(from: tokens)
                } else {
                    var plainText = tokens.compactMap { token -> String? in
                        if case .text(let value) = token { return value }
                        return nil
                    }.joined().trimmingCharacters(in: .whitespacesAndNewlines)

                    if !plainText.isEmpty {
                        if let refined = await refineWithTimeout(transcript: plainText) {
                            if let prevFix = refined.prevFix, !lastChunkInserted.isEmpty {
                                onPreviousChunkCorrected?(lastChunkInserted, prevFix)
                            }
                            if let refinedText = refined.refined, !refinedText.isEmpty {
                                plainText = refinedText
                            }
                        }
                        plainText = normalizePunctuation(plainText)
                        if lastChunkEndedWithStop {
                            plainText = " " + plainText.prefix(1).uppercased() + plainText.dropFirst()
                        }
                        lastChunkEndedWithStop = plainText.range(of: "[.?]\\s*$", options: .regularExpression) != nil
                        runningContext = trimContext(runningContext + " " + plainText)
                        lastChunkInserted = plainText
                    }
                    result = formattingState.buildRuns(from: [.text(plainText)])
                }
                onChunkApplied?(result.text)

                var shouldStop = !isActive
                for command in result.sessionCommands {
                    switch command {
                    case .undo: onUndoRequested?()
                    case .redo: onRedoRequested?()
                    case .stop: shouldStop = true
                    default: break
                    }
                }
                if shouldStop {
                    isActive = false
                    onHalted?(.userStopped)
                    return
                }
            } catch let APIError.server(status, message) where status == 402 {
                recorder.discardRecording()
                isActive = false
                onHalted?(.planLimitReached(message ?? "You've reached your dictation limit this month."))
                return
            } catch APIError.unauthorized {
                recorder.discardRecording()
                isActive = false
                onHalted?(.error("Not signed in — please log in again."))
                return
            } catch {
                recorder.discardRecording()
                isActive = false
                onHalted?(.error("Couldn't reach the server — check your connection and try again."))
                return
            }
        }
    }

    /// Races the refine call against a 7s timeout (matching web's
    /// `AbortController`) — a sibling task cancels the refine task, and
    /// `URLSession`'s async API honors Swift task cancellation, so this is
    /// a real cancel, not just a race. Any failure (timeout, network,
    /// decoding) returns nil, same as web's catch-and-proceed-with-raw-text.
    private func refineWithTimeout(transcript: String) async -> RefineResponse? {
        let refineTask = Task {
            try await docsService.refine(
                transcript: transcript, context: runningContext, prevChunk: lastChunkInserted, demoContext: demoContext
            )
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(7))
            refineTask.cancel()
        }
        defer { timeoutTask.cancel() }
        return try? await refineTask.value
    }

    /// Ported directly from docs.js's two local (non-Claude) fixups:
    /// within-chunk, a full stop or question mark followed by whitespace
    /// gets a double space and the next letter capitalized.
    private func normalizePunctuation(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "([.?])\\s+([a-zA-Z])") else { return text }
        let ns = text as NSString
        var output = ""
        var lastEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let punctuation = ns.substring(with: match.range(at: 1))
            let letter = ns.substring(with: match.range(at: 2)).uppercased()
            output += punctuation + "  " + letter
            lastEnd = match.range.location + match.range.length
        }
        output += ns.substring(from: lastEnd)
        return output
    }

    /// Ported from docs.js's trimContext — keeps the running context
    /// bounded so refine's token cost doesn't grow unbounded over a long
    /// dictation session.
    private func trimContext(_ text: String, maxWords: Int = 300) -> String {
        let words = text.split(separator: " ").filter { !$0.isEmpty }
        return words.suffix(maxWords).joined(separator: " ")
    }
}

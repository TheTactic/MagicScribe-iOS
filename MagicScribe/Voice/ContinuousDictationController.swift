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
    private let chunkDuration: TimeInterval
    private let languageProvider: () -> String

    /// Bumped only by `cancel()` — a hard stop that abandons whatever's
    /// in-flight right now. Graceful `stop()` leaves this unchanged so the
    /// loop still finalizes and applies the chunk already in progress
    /// (the user's last few seconds of speech shouldn't just vanish).
    private var generation = 0
    private var currentRecorder: AudioRecorder?
    private var loopTask: Task<Void, Never>?

    var onChunkApplied: ((AttributedString) -> Void)?
    var onHalted: ((HaltReason) -> Void)?
    var onUndoRequested: (() -> Void)?
    var onRedoRequested: (() -> Void)?

    init(
        formattingState: DocFormattingState,
        speechService: SpeechService? = nil,
        chunkDuration: TimeInterval = 50,
        language: @escaping () -> String
    ) {
        self.formattingState = formattingState
        // Constructed in the body, not as a default argument value — a
        // default argument expression evaluates in a context that doesn't
        // reliably inherit this MainActor-isolated init's isolation.
        self.speechService = speechService ?? SpeechService()
        self.chunkDuration = chunkDuration
        self.languageProvider = language
    }

    @discardableResult
    func start() async -> Bool {
        guard !isActive else { return true }
        guard await AudioRecorder().requestPermission() else { return false }
        isActive = true
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
                    fileURL: fileURL, language: languageProvider(), context: "docs"
                )
                recorder.discardRecording()
                guard generation == myGeneration else { return }

                let tokens = MagicCommandParser.tokenize(transcript)
                let result = formattingState.buildRuns(from: tokens)
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
            } catch {
                recorder.discardRecording()
                isActive = false
                onHalted?(.error("Couldn't reach the server — check your connection and try again."))
                return
            }
        }
    }
}

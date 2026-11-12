import Foundation

/// Owns the one-shot recording lifecycle for Voice Edit ("speak an
/// instruction about the document" rather than dictating content).
///
/// Deliberately NOT chunked like ContinuousDictationController — faithful
/// port of web's recordEditChunk(): one recording window (up to 60s, ended
/// early by the caller), transcribed in a single Whisper call, with the
/// whole transcript handed off as one instruction. Nothing is interpreted
/// as a running "open span" the way dictation's bold/italic state is.
@MainActor
final class VoiceEditController {
    enum Outcome {
        case undo
        case redo
        case applied([EditOperation])
        case noMatch
        case upgradeRequired(String)
        case error(String)
    }

    private(set) var isActive = false

    private let speechService: SpeechService
    private let docsService: DocsService
    private let languageProvider: () -> String
    private var recorder: AudioRecorder?

    init(
        speechService: SpeechService? = nil,
        docsService: DocsService = DocsService(),
        language: @escaping () -> String
    ) {
        // Constructed in the body, not as a default argument value — same
        // reason as ContinuousDictationController's identical pattern.
        self.speechService = speechService ?? SpeechService()
        self.docsService = docsService
        self.languageProvider = language
    }

    @discardableResult
    func start() async -> Bool {
        guard !isActive else { return true }
        guard await AudioRecorder().requestPermission() else { return false }
        let newRecorder = AudioRecorder(maxDuration: 60)
        do {
            try newRecorder.start()
        } catch {
            return false
        }
        recorder = newRecorder
        isActive = true
        return true
    }

    /// Stops the recording and resolves the instruction. A local undo/redo
    /// phrase short-circuits before any network call — same as web's
    /// matchEditUndoRedo — otherwise the transcript plus the document's
    /// current paragraph chunks go to api/edit.php. The caller applies the
    /// returned operations itself (this controller doesn't own the
    /// document text or undo stack).
    func finish(documentText: AttributedString) async -> Outcome {
        guard isActive, let activeRecorder = recorder else { return .error("Not recording.") }
        isActive = false
        recorder = nil
        defer { activeRecorder.discardRecording() }

        guard let fileURL = activeRecorder.stop() else {
            return .noMatch
        }

        do {
            let transcript = try await speechService.transcribe(
                fileURL: fileURL, language: languageProvider(), context: "docs"
            )
            guard !WhisperHallucinationFilter.isHallucination(transcript) else {
                return .noMatch
            }
            if let match = DocVoiceEditExecutor.matchUndoRedo(transcript) {
                return match == .undo ? .undo : .redo
            }

            let chunks = DocVoiceEditExecutor.chunks(from: documentText)
            let operations = try await docsService.requestVoiceEdit(instruction: transcript, chunks: chunks)
            return operations.isEmpty ? .noMatch : .applied(operations)
        } catch let DocsServiceError.upgradeRequired(message, _) {
            return .upgradeRequired(message)
        } catch {
            return .error("Voice edit failed — check your connection and try again.")
        }
    }

    /// Hard stop: abandon whatever's in flight, no transcription.
    func cancel() {
        isActive = false
        recorder?.discardRecording()
        recorder = nil
    }
}

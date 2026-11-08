import AVFoundation

enum AudioRecorderError: Error {
    case permissionDenied
    case recordingFailed
}

/// Thin AVAudioRecorder wrapper — standalone and reusable (not onboarding-
/// specific), so the real post-paywall Filler feature can reuse it directly
/// later. Records to a temp .m4a (AAC) file, since iOS can't natively produce
/// the webm/opus the web app's MediaRecorder does — speech.php just forwards
/// whatever file/mime it receives to Whisper, which accepts .m4a directly.
@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var autoStopTask: Task<Void, Never>?

    /// Safety cap — this is a one-utterance demo field, not open-ended
    /// dictation, so this is much shorter than the web Filler's 60s cap.
    private let maxDuration: TimeInterval = 15

    func requestPermission() async -> Bool {
        #if os(iOS)
        await AVAudioApplication.requestRecordPermission()
        #else
        true
        #endif
    }

    func start() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        #endif

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        newRecorder.delegate = self
        guard newRecorder.record() else {
            throw AudioRecorderError.recordingFailed
        }

        recorder = newRecorder
        recordingURL = url
        isRecording = true

        autoStopTask = Task { @MainActor [weak self, maxDuration] in
            try? await Task.sleep(for: .seconds(maxDuration))
            self?.stop()
        }
    }

    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return recordingURL }
        autoStopTask?.cancel()
        recorder?.stop()
        isRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
        return recordingURL
    }

    /// Call once the recording has been uploaded (or abandoned) to clean up
    /// the temp file.
    func discardRecording() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }
}

import SwiftUI

/// Real voice capture + magic-command detection (MagicCommandParser) — no
/// AI/Claude call needed, formatting is parsed entirely locally once the
/// transcript is in hand, same as the real Docs product. Only reachable via
/// the Business tier's demo set (Docs is a Business-gated feature).
struct DemoDocView: View {
    let coordinator: OnboardingCoordinator

    private enum Stage {
        case idle, recording, processing, applied
    }

    @State private var stage: Stage = .idle
    @State private var displayText = "Speak to transcribe your document..."
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderline = false
    @State private var headingLevel: Int?
    @State private var errorMessage: String?
    // @State, not `let` — must be the same instance across the "tap to
    // start" and "tap to stop" interactions, which are separate re-renders.
    @State private var audioRecorder = AudioRecorder()

    private let speechService = SpeechService()

    var body: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Try a magic voice command")
                    .font(.title.bold())
                    .foregroundStyle(Color.magicNavy)
                Text(stageInstruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(displayText)
                .font(bodyFont)
                .underline(isUnderline)
                .foregroundStyle(Color.magicNavy)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button {
                Task { await handleTap() }
            } label: {
                Group {
                    if stage == .processing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 36))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(stage == .recording ? Color.magicGold : Color.magicBlue)
                .clipShape(Circle())
                .scaleEffect(stage == .recording ? 1.1 : 1)
            }
            .buttonStyle(.plain)
            .disabled(stage == .processing || stage == .applied)
            .animation(.spring(response: 0.3), value: stage)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if stage == .applied {
                Button {
                    coordinator.completeDemo(.completed)
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.magicBlue)
            } else {
                Button("Skip this demo") {
                    audioRecorder.discardRecording()
                    coordinator.completeDemo(.skipped)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var bodyFont: Font {
        switch headingLevel {
        case 1: .largeTitle.bold()
        case 2: .title.bold()
        case 3: .title2.bold()
        default:
            isBold ? (isItalic ? Font.body.bold().italic() : Font.body.bold())
                   : (isItalic ? Font.body.italic() : Font.body)
        }
    }

    private var stageInstruction: String {
        switch stage {
        case .idle: "Tap the mic, then say: \"magic bold on.\""
        case .recording: "Listening — tap again when you're done."
        case .processing: "Working on it..."
        case .applied: "Nice!"
        }
    }

    private func handleTap() async {
        switch stage {
        case .idle:
            await startRecording()
        case .recording:
            await stopAndProcess()
        case .processing, .applied:
            break
        }
    }

    private func startRecording() async {
        errorMessage = nil
        guard await audioRecorder.requestPermission() else {
            errorMessage = "Microphone access is off — enable it in Settings to try this."
            return
        }
        do {
            try audioRecorder.start()
            stage = .recording
        } catch {
            errorMessage = "Couldn't start recording — try again."
        }
    }

    private func stopAndProcess() async {
        guard let fileURL = audioRecorder.stop() else {
            errorMessage = "Couldn't start recording — try again."
            stage = .idle
            return
        }
        stage = .processing
        defer { audioRecorder.discardRecording() }
        do {
            let transcript = try await speechService.transcribe(
                fileURL: fileURL, language: "en", context: "ios_onboarding_demo_docs"
            )
            apply(MagicCommandParser.tokenize(transcript))
        } catch let SpeechServiceError.transcriptionFailed(message) {
            errorMessage = message
            stage = .idle
        } catch let APIError.server(_, message) {
            errorMessage = message ?? "Something went wrong — please try again."
            stage = .idle
        } catch APIError.unauthorized {
            errorMessage = "Not signed in — this demo needs a valid account."
            stage = .idle
        } catch APIError.decoding {
            errorMessage = "Got an unexpected response from the server."
            stage = .idle
        } catch {
            errorMessage = "Couldn't reach the server: \(error)"
            stage = .idle
        }
    }

    /// Any recognized magic command counts as a completed demo, not just
    /// "magic bold on" — the real system, not one hardcoded path. Caps/undo/
    /// redo/stop are recognized (count toward success) but have no visual
    /// effect in this simple preview; bold/italic/underline/heading/new-
    /// paragraph/new-line all apply for real.
    private func apply(_ tokens: [MagicToken]) {
        var foundCommand = false
        var dictatedText = ""

        for token in tokens {
            switch token {
            case .text(let text):
                dictatedText += text
            case .command(let command):
                foundCommand = true
                switch command {
                case .boldOn: isBold = true
                case .boldOff: isBold = false
                case .bold: isBold.toggle()
                case .italicOn: isItalic = true
                case .italicOff: isItalic = false
                case .italic: isItalic.toggle()
                case .underlineOn: isUnderline = true
                case .underlineOff: isUnderline = false
                case .underline: isUnderline.toggle()
                case .h1: headingLevel = 1
                case .h2: headingLevel = 2
                case .h3: headingLevel = 3
                case .headingOff: headingLevel = nil
                case .newParagraph: dictatedText += "\n\n"
                case .newLine: dictatedText += "\n"
                case .capsOn, .capsOff, .capsToggle, .undo, .redo, .stop:
                    break
                }
            }
        }

        let trimmedDictation = dictatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDictation.isEmpty {
            displayText = trimmedDictation
        }

        if foundCommand {
            stage = .applied
        } else {
            errorMessage = "Didn't catch a magic command — try again."
            stage = .idle
        }
    }
}

#Preview {
    DemoDocView(coordinator: OnboardingCoordinator())
}

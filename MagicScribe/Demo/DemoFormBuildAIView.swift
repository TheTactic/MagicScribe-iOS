import SwiftUI

/// Builder Pro / Business's Build demo: describe a form out loud and have
/// Claude build it — the actual thing these tiers pay extra for, vs.
/// Filler Pro's manual drag-and-drop. Real transcription (api/speech.php)
/// + real build_form call (api/ai.php), same "ios_onboarding_demo" /
/// "ios_onboarding_demo_build" bypass contexts already proven for the
/// Fill and Doc demos.
struct DemoFormBuildAIView: View {
    let coordinator: OnboardingCoordinator

    private enum Stage {
        case idle, recording, processing, built
    }

    private static let guidePhrase = "Build a form that asks for someone's full name and whether they agree to the terms."

    @State private var stage: Stage = .idle
    @State private var builtFields: [BuiltFieldDescriptor] = []
    @State private var errorMessage: String?
    @State private var audioRecorder = AudioRecorder()

    private let speechService = SpeechService()

    var body: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Try building a form with AI")
                    .font(.title.bold())
                    .foregroundStyle(Color.magicNavy)
                Text(stageInstruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if stage == .idle || stage == .recording {
                Text("\u{201C}\(Self.guidePhrase)\u{201D}")
                    .font(.title3.weight(.medium))
                    .italic()
                    .foregroundStyle(Color.magicNavy)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if stage == .built {
                builtFieldsList
            }

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
            .disabled(stage == .processing || stage == .built)
            .animation(.spring(response: 0.3), value: stage)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if stage == .built {
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

    private var builtFieldsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(builtFields.enumerated()), id: \.offset) { _, field in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: field.type))
                        .foregroundStyle(Color.magicBlue)
                        .frame(width: 20)
                    Text(field.label)
                        .foregroundStyle(Color.magicNavy)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "text", "textarea": "text.cursor"
        case "checkbox": "checkmark.square"
        case "dropdown": "chevron.down.square"
        case "date": "calendar"
        case "signature": "signature"
        case "image": "photo"
        default: "square.text.square"
        }
    }

    private var stageInstruction: String {
        switch stage {
        case .idle: "Tap the mic and read the phrase below."
        case .recording: "Listening — tap again when you're done."
        case .processing: "Building your form..."
        case .built: "Here's what AI built:"
        }
    }

    private func handleTap() async {
        switch stage {
        case .idle:
            await startRecording()
        case .recording:
            await stopAndProcess()
        case .processing, .built:
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
                fileURL: fileURL, language: "en", context: "ios_onboarding_demo"
            )
            let response = try await speechService.buildForm(
                description: transcript, context: "ios_onboarding_demo_build"
            )
            if let fields = response.fields, !fields.isEmpty {
                builtFields = fields
                stage = .built
            } else {
                errorMessage = "Didn't catch enough to build a form — try again."
                stage = .idle
            }
        } catch let SpeechServiceError.transcriptionFailed(message) {
            errorMessage = message
            stage = .idle
        } catch let SpeechServiceError.buildFailed(message) {
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
}

#Preview {
    DemoFormBuildAIView(coordinator: OnboardingCoordinator())
}

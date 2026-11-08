import SwiftUI

/// Real voice capture + AI field mapping — the first non-scripted demo
/// screen. Uses the "ios_onboarding_demo" context so a Free-plan account
/// (every fresh signup) can try the real pipeline a few times before
/// hitting the normal voice_fill plan gate — see api/speech.php, api/ai.php.
struct DemoFormFillView: View {
    let coordinator: OnboardingCoordinator

    private enum Stage {
        case idle, recording, processing, filled
    }

    @State private var stage: Stage = .idle
    @State private var filledName: String?
    @State private var errorMessage: String?
    // @State, not `let` — must be the same instance across the "tap to
    // start" and "tap to stop" interactions, which are separate re-renders.
    @State private var audioRecorder = AudioRecorder()

    private let speechService = SpeechService()

    var body: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Try filling a form by voice")
                    .font(.title.bold())
                    .foregroundStyle(Color.magicNavy)
                Text(stageInstruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Full Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(filledName ?? "—")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(filledName == nil ? .secondary : Color.magicNavy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            .disabled(stage == .processing || stage == .filled)
            .animation(.spring(response: 0.3), value: stage)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if stage == .filled {
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

    private var stageInstruction: String {
        switch stage {
        case .idle: "Tap the mic, then say your name."
        case .recording: "Listening — tap again when you're done."
        case .processing: "Working on it..."
        case .filled: "Nice!"
        }
    }

    private func handleTap() async {
        switch stage {
        case .idle:
            await startRecording()
        case .recording:
            await stopAndProcess()
        case .processing, .filled:
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
            let field = FormFieldDescriptor(id: "full_name", label: "Full Name", type: "text")
            let mapping = try await speechService.mapFields(
                transcript: transcript, fields: [field], context: "ios_onboarding_demo"
            )
            if let value = mapping["full_name"] ?? nil, !value.isEmpty {
                filledName = value
                stage = .filled
            } else {
                errorMessage = "Didn't catch a name in that — try again."
                stage = .idle
            }
        } catch let SpeechServiceError.transcriptionFailed(message) {
            errorMessage = message
            stage = .idle
        } catch let SpeechServiceError.mappingFailed(message) {
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
            // Temporary: surface the raw error instead of a generic guess,
            // so a real failure here is immediately actionable instead of
            // needing another round of blind debugging.
            errorMessage = "Couldn't reach the server: \(error)"
            stage = .idle
        }
    }
}

#Preview {
    DemoFormFillView(coordinator: OnboardingCoordinator())
}

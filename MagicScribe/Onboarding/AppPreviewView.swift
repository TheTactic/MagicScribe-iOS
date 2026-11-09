import SwiftUI

struct AppPreviewView: View {
    let coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            AppPreviewMockup()
                .frame(maxWidth: 280)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 12)

            VStack(spacing: 8) {
                Text("This is MagicScribe")
                    .font(.title.bold())
                    .foregroundStyle(Color.magicNavy)
                Text("Speak, and watch your words become a polished document — no typing required.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("Form building and filling are available on the web at magicscribe.tech.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button {
                coordinator.advance(to: .demoDoc)
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.magicBlue)
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

/// Stand-in for a real app screenshot — swap for `Image("AppPreviewPlaceholder")`
/// once real product screens exist to photograph.
private struct AppPreviewMockup: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Color.magicNavy)
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.magicGold)
                    Text("\"Magic bold on...\"")
                        .font(.callout.italic())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
    }
}

#Preview {
    AppPreviewView(coordinator: OnboardingCoordinator())
}

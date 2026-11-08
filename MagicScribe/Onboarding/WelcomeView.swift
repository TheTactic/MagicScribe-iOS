import SwiftUI

struct WelcomeView: View {
    let coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "wand.and.stars")
                .font(.system(size: 56))
                .foregroundStyle(Color.magicGold)

            VStack(spacing: 8) {
                Text("MagicScribe")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.magicNavy)
                Text("Voice-first forms and docs — just speak.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    coordinator.advance(to: .signup)
                } label: {
                    Text("Create Account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.magicBlue)

                Button("Log In") {
                    coordinator.advance(to: .login)
                }
                .font(.subheadline)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    WelcomeView(coordinator: OnboardingCoordinator())
}

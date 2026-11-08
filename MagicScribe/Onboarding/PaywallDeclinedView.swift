import SwiftUI

/// Reusable beyond onboarding — e.g. a future Settings "Upgrade" row can present this
/// same view, not just the one-time moment right after declining.
struct PaywallDeclinedView: View {
    let coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "wand.and.stars")
                .font(.system(size: 56))
                .foregroundStyle(Color.magicGold)

            VStack(spacing: 8) {
                Text("You're in demo mode")
                    .font(.title.bold())
                    .foregroundStyle(Color.magicNavy)
                Text("Keep exploring with the demo — upgrade anytime to unlock the real thing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    coordinator.reconsiderPaywall()
                } label: {
                    Text("See plans")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.magicBlue)

                Button("Continue") {
                    coordinator.finishOnboarding()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    PaywallDeclinedView(coordinator: OnboardingCoordinator())
}

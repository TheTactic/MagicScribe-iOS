import SwiftUI

struct CelebrationView: View {
    let coordinator: OnboardingCoordinator

    var body: some View {
        ZStack {
            Color.magicNavy.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.magicGold)

                VStack(spacing: 8) {
                    Text("Nicely done!")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("That's exactly how it works in the real app.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button {
                    coordinator.advance(to: .paywall)
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.magicGold)
                .padding(.horizontal)
            }
            .padding(.vertical, 40)

            ConfettiView()
        }
    }
}

#Preview {
    CelebrationView(coordinator: OnboardingCoordinator())
}

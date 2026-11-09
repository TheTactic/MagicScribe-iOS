import SwiftUI

/// Orphaned, not deleted — iOS v1 ships a single product (Voice Pro), so
/// there's no tier to pick between and this view isn't reachable from the
/// active onboarding flow. Kept for a possible future multi-tier revival;
/// `coordinator.selectTier(_:)` no longer exists, so the button is a no-op
/// until/unless this comes back.
struct TierQuizView: View {
    let coordinator: OnboardingCoordinator

    private struct Option {
        let tier: PricingTierID
        let title: String
        let icon: String
    }

    private let options: [Option] = [
        Option(tier: .fillerPro, title: "Fill forms and dictate documents by voice", icon: "mic.fill"),
        Option(tier: .builderPro, title: "Build forms with AI, fill forms by voice, dictate docs by voice", icon: "square.and.pencil"),
        Option(tier: .business, title: "Everything, plus my team (5 members)", icon: "person.3.fill"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How will you be using MagicScribe?")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.magicNavy)
                Text("We'll tailor the next few screens to you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                ForEach(options, id: \.tier) { option in
                    Button {
                        // No-op — see type doc comment.
                    } label: {
                        HStack {
                            Image(systemName: option.icon)
                                .font(.title2)
                                .foregroundStyle(Color.magicBlue)
                                .frame(width: 36)
                            Text(option.title)
                                .font(.headline)
                                .foregroundStyle(Color.magicNavy)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    TierQuizView(coordinator: OnboardingCoordinator())
}

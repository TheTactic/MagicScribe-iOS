import SwiftUI

struct OnboardingFlowView: View {
    @State private var coordinator: OnboardingCoordinator
    private let onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        _coordinator = State(initialValue: OnboardingCoordinator())
    }

    var body: some View {
        Group {
            switch coordinator.currentStep {
            case .welcome:
                WelcomeView(coordinator: coordinator)
            case .login:
                LoginView(coordinator: coordinator)
            case .signup:
                SignupView(coordinator: coordinator)
            case .verifyEmail:
                VerifyEmailView(
                    email: coordinator.signupEmail,
                    initialDeliveryFailed: coordinator.initialEmailDeliveryFailed,
                    onVerified: { coordinator.verifyEmailSucceeded() },
                    onDismiss: { coordinator.skipEmailVerification() }
                )
            case .appPreview:
                AppPreviewView(coordinator: coordinator)
            case .demoDoc:
                // The real editor, not a separate demo implementation —
                // whatever they create here becomes their actual first
                // saved document rather than a disposable preview.
                NavigationStack {
                    DocsEditorView(
                        docId: nil,
                        onSaved: { coordinator.completeDemo(.completed) },
                        isOnboardingDemo: true,
                        onSkipped: { coordinator.completeDemo(.skipped) }
                    )
                }
            case .celebration:
                CelebrationView(coordinator: coordinator)
            case .paywall:
                // Single choke point for every path into .paywall (fresh
                // completion, or declinePaywall's "See plans" ->
                // reconsiderPaywall()) — an already-entitled account (e.g.
                // an existing web subscriber) should never see the purchase
                // screen at all.
                if let plan = coordinator.currentUserPlan, plan != "free" {
                    Color.clear.onAppear { coordinator.finishOnboarding() }
                } else {
                    PaywallView(coordinator: coordinator)
                }
            case .declinedPaywall:
                PaywallDeclinedView(coordinator: coordinator)
            }
        }
        .animation(.easeInOut, value: coordinator.currentStep)
        .onAppear {
            coordinator.onFinished = onFinished
        }
    }
}

#Preview {
    OnboardingFlowView(onFinished: {})
        .environment(StoreKitManager())
}

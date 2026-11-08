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
                    onVerified: { coordinator.verifyEmailSucceeded() },
                    onDismiss: { coordinator.skipEmailVerification() }
                )
            case .appPreview:
                AppPreviewView(coordinator: coordinator)
            case .tierQuiz:
                TierQuizView(coordinator: coordinator)
            case .demoFormBuild:
                if coordinator.selectedTier == .fillerPro {
                    DemoFormBuildManualView(coordinator: coordinator)
                } else {
                    DemoFormBuildAIView(coordinator: coordinator)
                }
            case .demoFormFill:
                DemoFormFillView(coordinator: coordinator)
            case .demoDoc:
                DemoDocView(coordinator: coordinator)
            case .celebration:
                CelebrationView(coordinator: coordinator)
            case .paywall:
                PaywallView(coordinator: coordinator)
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

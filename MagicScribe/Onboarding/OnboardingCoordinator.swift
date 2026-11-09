import Foundation

enum OnboardingStep: Equatable {
    case welcome
    case login
    case signup
    case verifyEmail
    case appPreview
    case demoDoc
    case celebration
    case paywall
    case declinedPaywall
}

/// Enum-driven state machine for onboarding. Deliberately not a NavigationStack:
/// the flow is a small closed set of linear steps with one required bottleneck
/// (the hard paywall), and an explicit `currentStep` makes "no way back past the
/// paywall" the default rather than something fought for against back-swipe.
@Observable
final class OnboardingCoordinator {
    private(set) var currentStep: OnboardingStep

    /// Captured at signup, used to personalize the Form-Fill demo for free.
    var signupFullName: String = ""
    /// Captured at signup, shown on the verify-email screen ("we sent a code to ___").
    private(set) var signupEmail: String = ""
    private(set) var emailVerified: Bool
    /// Captured from the same auth response as signupEmail/emailVerified —
    /// lets the paywall step skip itself for an already-entitled account
    /// (e.g. an existing web subscriber whose email happens to need
    /// re-verification in-app) without a separate network call.
    private(set) var currentUserPlan: String?

    private let state: OnboardingState
    var onFinished: (() -> Void)?

    init(
        startingAt step: OnboardingStep = .welcome,
        state: OnboardingState = OnboardingState()
    ) {
        self.currentStep = step
        self.state = state
        self.emailVerified = state.cachedEmailVerified
    }

    func advance(to step: OnboardingStep) {
        currentStep = step
    }

    /// Called right after a successful signup, or after `LoginView` recovers an
    /// unverified account via `AuthService.recoverVerification` — either way,
    /// advances into the (skippable) in-app verification code screen.
    func recordSignupAccount(_ account: UserAccount) {
        signupFullName = account.fullName
        signupEmail = account.email
        emailVerified = account.emailVerified
        currentUserPlan = account.plan
        state.cachedEmailVerified = account.emailVerified
        currentStep = .verifyEmail
    }

    func verifyEmailSucceeded() {
        emailVerified = true
        state.cachedEmailVerified = true
        currentStep = .appPreview
    }

    func skipEmailVerification() {
        currentStep = .appPreview
    }

    /// Celebration only fires if the demo was actually completed, not just
    /// skipped — the confetti is meant to be earned.
    func completeDemo(_ outcome: DemoOutcome) {
        currentStep = (outcome == .completed) ? .celebration : .paywall
    }

    func declinePaywall() {
        state.didDeclinePaywall = true
        currentStep = .declinedPaywall
    }

    /// Re-entry point into the paywall from the "demo mode" nudge — also usable
    /// later from inside the main app (e.g. a Settings "Upgrade" row), not onboarding-exclusive.
    func reconsiderPaywall() {
        currentStep = .paywall
    }

    /// Also called directly by `LoginView` on a successful login — a returning
    /// user skips the entire demo/paywall funnel, same end state as finishing it.
    func finishOnboarding() {
        state.hasCompletedOnboarding = true
        onFinished?()
    }
}

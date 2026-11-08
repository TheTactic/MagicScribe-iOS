import Foundation

enum OnboardingStep: Equatable {
    case welcome
    case login
    case signup
    case verifyEmail
    case appPreview
    case tierQuiz
    case demoFormBuild
    case demoFormFill
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
    private(set) var selectedTier: PricingTierID?

    /// Captured at signup, used to personalize the Form-Fill demo for free.
    var signupFullName: String = ""
    /// Captured at signup, shown on the verify-email screen ("we sent a code to ___").
    private(set) var signupEmail: String = ""
    private(set) var emailVerified: Bool

    private var demoQueue: [OnboardingStep] = []
    private var completedAnyDemo = false

    private let state: OnboardingState
    var onFinished: (() -> Void)?

    init(
        startingAt step: OnboardingStep = .welcome,
        tier: PricingTierID? = nil,
        state: OnboardingState = OnboardingState()
    ) {
        self.currentStep = step
        self.selectedTier = tier
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

    /// Only the demo(s) matching the chosen tier are shown — not the full set —
    /// so the confetti-then-paywall moment stays causally tied to what's being sold.
    func selectTier(_ tier: PricingTierID) {
        selectedTier = tier
        completedAnyDemo = false
        demoQueue = Self.demoSteps(for: tier)
        advanceToNextDemoOrCelebration()
    }

    func completeDemo(_ outcome: DemoOutcome) {
        if outcome == .completed {
            completedAnyDemo = true
        }
        advanceToNextDemoOrCelebration()
    }

    /// Celebration only fires if a demo in the chosen tier's set was actually
    /// completed, not just skipped — the confetti is meant to be earned.
    private func advanceToNextDemoOrCelebration() {
        if !demoQueue.isEmpty {
            currentStep = demoQueue.removeFirst()
        } else if completedAnyDemo {
            currentStep = .celebration
        } else {
            currentStep = .paywall
        }
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

    /// All three purchasable tiers now share the same three core capabilities
    /// (voice fill, form building, Docs dictation) — only AI-assist and team
    /// size differ between them, and the current scripted demos can't
    /// distinguish those. So every tier gets the same demo set.
    private static func demoSteps(for tier: PricingTierID) -> [OnboardingStep] {
        switch tier {
        case .fillerPro, .builderPro, .business:
            [.demoFormBuild, .demoFormFill, .demoDoc]
        case .businessPlus, .enterprise:
            []
        }
    }
}

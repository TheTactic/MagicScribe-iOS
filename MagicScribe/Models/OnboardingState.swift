import Foundation

/// Non-secret, read-through UserDefaults flags for onboarding/paywall progress.
/// Keychain ("who are you") and OnboardingState ("where are you in the product")
/// are deliberately separate stores — nothing credential-shaped belongs here.
struct OnboardingState {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        static let hasCompletedOnboarding = "onboarding.hasCompletedOnboarding"
        static let didDeclinePaywall = "onboarding.didDeclinePaywall"
        static let cachedEmailVerified = "onboarding.cachedEmailVerified"
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        nonmutating set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    var didDeclinePaywall: Bool {
        get { defaults.bool(forKey: Keys.didDeclinePaywall) }
        nonmutating set { defaults.set(newValue, forKey: Keys.didDeclinePaywall) }
    }

    /// Advisory cache of the server's `email_verified` flag, refreshed whenever
    /// a fresh `UserAccount` comes back (signup, or a successful code verify).
    /// Not a source of truth for anything security-sensitive — just lets the UI
    /// decide whether to show a "verify your email" reminder without a network call.
    var cachedEmailVerified: Bool {
        get { defaults.bool(forKey: Keys.cachedEmailVerified) }
        nonmutating set { defaults.set(newValue, forKey: Keys.cachedEmailVerified) }
    }
}

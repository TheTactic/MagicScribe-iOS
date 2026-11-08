import SwiftUI

@main struct MyApp: App {
    @State private var hasCompletedOnboarding = OnboardingState().hasCompletedOnboarding
    @State private var storeKitManager = StoreKitManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainAppShellView(onSignOut: signOut)
                } else {
                    OnboardingFlowView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environment(storeKitManager)
            .task {
                await storeKitManager.refreshEntitlements()
            }
        }
    }

    /// Demo-only reset: clears the local token and onboarding flags so the
    /// app restarts at signup, without reinstalling. Local state only — no
    /// backend call, no account deletion.
    private func signOut() {
        KeychainTokenStore().deleteToken()
        let state = OnboardingState()
        state.hasCompletedOnboarding = false
        state.didDeclinePaywall = false
        state.cachedEmailVerified = false
        hasCompletedOnboarding = false
    }
}

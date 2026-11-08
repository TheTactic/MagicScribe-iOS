import SwiftUI

/// Closure-driven, not coupled to a concrete OnboardingCoordinator reference,
/// so this screen can be reopened later from inside the main app (e.g. a
/// reminder entry point) without onboarding-specific plumbing — same intent
/// as PaywallDeclinedView's reusability note.
struct VerifyEmailView: View {
    let email: String
    let onVerified: () -> Void
    let onDismiss: () -> Void

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var resendConfirmation: String?
    @State private var resendCooldown = 0
    @FocusState private var isCodeFieldFocused: Bool

    private let authService = AuthService()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.magicGold)
                Text("Check your email")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.magicNavy)
                Text(email.isEmpty ? "Enter the 6-digit code we sent you." : "Enter the 6-digit code we sent to \(email).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("123456", text: $code)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .multilineTextAlignment(.center)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .kerning(8)
                .padding(.vertical, 12)
                .frame(maxWidth: 220)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .focused($isCodeFieldFocused)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter(\.isNumber).prefix(6))
                    if code.count == 6 && !isSubmitting {
                        Task { await submit() }
                    }
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let resendConfirmation {
                Text(resendConfirmation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    isCodeFieldFocused = false
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Verify").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.magicBlue)
                .disabled(code.count != 6 || isSubmitting)

                Button {
                    Task { await resend() }
                } label: {
                    Text(resendCooldown > 0 ? "Resend code (\(resendCooldown)s)" : (isResending ? "Sending..." : "Resend code"))
                }
                .font(.footnote)
                .disabled(isResending || resendCooldown > 0)

                Button("Skip for now", action: onDismiss)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { isCodeFieldFocused = true }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await authService.verifyEmailCode(code)
            onVerified()
        } catch let APIError.server(_, message) {
            // Surfaces the backend's real reason: incorrect vs. expired code,
            // or a rate limit — not a blanket "didn't work."
            errorMessage = message ?? "That code didn't work — check it and try again."
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }

    private func resend() async {
        errorMessage = nil
        resendConfirmation = nil
        isResending = true
        defer { isResending = false }
        do {
            try await authService.resendVerificationCode()
            resendConfirmation = "A new code is on its way."
            startResendCooldown()
        } catch let APIError.server(_, message) {
            errorMessage = message ?? "Couldn't send a new code — try again shortly."
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }

    /// Mirrors the backend's own resend rate limit (3 per 15 min) with a short,
    /// user-visible cooldown so repeated taps don't look like they're doing nothing.
    private func startResendCooldown() {
        resendCooldown = 30
        Task {
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendCooldown -= 1
            }
        }
    }
}

#Preview {
    VerifyEmailView(email: "alex@example.com", onVerified: {}, onDismiss: {})
}

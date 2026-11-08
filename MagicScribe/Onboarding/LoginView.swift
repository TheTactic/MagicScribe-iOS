import SwiftUI

struct LoginView: View {
    let coordinator: OnboardingCoordinator

    private enum Field {
        case email, password
    }

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showResendOption = false
    @State private var isRecovering = false
    @FocusState private var focusedField: Field?

    private let authService = AuthService()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.magicGold)
                    Text("Log in")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.magicNavy)
                    Text("Welcome back.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)

                    PasswordField(placeholder: "Password", text: $password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .onSubmit {
                    switch focusedField {
                    case .email: focusedField = .password
                    case .password, .none:
                        focusedField = nil
                        if canSubmit { Task { await submit() } }
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if showResendOption {
                    Button {
                        Task { await recoverVerification() }
                    } label: {
                        if isRecovering {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Resend verification code")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.magicBlue)
                    .disabled(isRecovering)
                }

                VStack(spacing: 12) {
                    Button {
                        focusedField = nil
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Log In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.magicBlue)
                    .disabled(!canSubmit || isSubmitting)

                    Button("Don't have an account? Sign Up") {
                        coordinator.advance(to: .signup)
                    }
                    .font(.footnote)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focusedField = .email }
    }

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty
    }

    private func submit() async {
        errorMessage = nil
        showResendOption = false
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await authService.login(email: email, password: password)
            coordinator.finishOnboarding()
        } catch let APIError.server(status, message) {
            // Surfaces the backend's real reason: wrong credentials, unverified
            // email, or a rate limit — not a blanket "something went wrong."
            errorMessage = message ?? "Something went wrong — please try again."
            // auth_token.php's only 403 is the unverified-email gate — offer the
            // way back in rather than leaving an unverified, signed-out user stuck.
            showResendOption = (status == 403)
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }

    /// For an account that's unverified and has no token to reach
    /// verify_email_code.php directly — validates credentials again and gets
    /// a fresh code + token in one call, then drops into the same verify screen.
    private func recoverVerification() async {
        errorMessage = nil
        isRecovering = true
        defer { isRecovering = false }
        do {
            let account = try await authService.recoverVerification(email: email, password: password)
            coordinator.recordSignupAccount(account)
        } catch let APIError.server(_, message) {
            errorMessage = message ?? "Something went wrong — please try again."
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }
}

#Preview {
    LoginView(coordinator: OnboardingCoordinator())
}

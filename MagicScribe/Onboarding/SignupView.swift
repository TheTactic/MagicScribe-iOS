import SwiftUI

struct SignupView: View {
    let coordinator: OnboardingCoordinator

    private enum Field {
        case fullName, email, password
    }

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private let authService = AuthService()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.magicGold)
                    Text("Create your account")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.magicNavy)
                    Text("Voice-first forms and docs — just speak.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 14) {
                    TextField("Full name", text: $fullName)
                        .textContentType(.name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .fullName)
                        .submitLabel(.next)

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

                    PasswordField(placeholder: "Password", text: $password, isNewPassword: true)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)

                    Text("At least 8 characters")
                        .font(.caption)
                        .foregroundStyle(password.isEmpty || password.count >= 8 ? Color.secondary : Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .onSubmit {
                    switch focusedField {
                    case .fullName: focusedField = .email
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

                VStack(spacing: 12) {
                    Button {
                        focusedField = nil
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.magicBlue)
                    .disabled(!canSubmit || isSubmitting)

                    Button("Already have an account? Log In") {
                        coordinator.advance(to: .login)
                    }
                    .font(.footnote)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focusedField = .fullName }
    }

    private var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@")
            && password.count >= 8
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let account = try await authService.register(email: email, password: password, fullName: fullName)
            coordinator.recordSignupAccount(account)
        } catch let APIError.server(_, message) {
            // Surface the backend's real reason (rate limit, duplicate email, etc.)
            // instead of a blanket message that makes a correctly-working rejection
            // look identical to a broken backend.
            errorMessage = message ?? "Something went wrong — please try again."
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }
}

#Preview {
    SignupView(coordinator: OnboardingCoordinator())
}

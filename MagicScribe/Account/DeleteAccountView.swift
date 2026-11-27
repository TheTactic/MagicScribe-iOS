import StoreKit
import SwiftUI

/// In-app account deletion — required by App Store Guideline 5.1.1(v) for
/// any app that supports account creation. Asks for the password as a
/// re-check, then a final "can't be undone" confirmation before calling
/// api/delete_account.php.
struct DeleteAccountView: View {
    /// Called after the server confirms deletion — resets the app to signup,
    /// same as signing out (the token is already cleared by AuthService).
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(StoreKitManager.self) private var storeKit
    @State private var password = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var isConfirming = false
    @State private var isShowingManageSubscriptions = false

    private let authService = AuthService()

    /// An Apple subscription can't be cancelled server-side, so a subscriber
    /// has to be told to cancel it themselves or they'll keep being billed.
    private var hasActiveSubscription: Bool {
        !storeKit.purchasedProductIDs.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently deletes your MagicScribe account and everything in it — your documents, images, and settings. This can't be undone.")
                        .foregroundStyle(Color.magicNavy)
                }

                Section {
                    Text(hasActiveSubscription
                         ? "You have an active Voice Pro subscription. Deleting your account doesn't cancel it — Apple bills it, so cancel it first to avoid being charged again."
                         : "If you subscribed to Voice Pro through Apple, deleting your account doesn't cancel it — cancel it in your Apple subscriptions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Manage Subscriptions") {
                        isShowingManageSubscriptions = true
                    }
                    .foregroundStyle(Color.magicBlueButton)
                } header: {
                    Text("Subscriptions")
                }

                Section {
                    PasswordField(placeholder: "Password", text: $password)
                        .onChange(of: password) { errorMessage = nil }
                } header: {
                    Text("Enter your password to confirm")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isConfirming = true
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView()
                            } else {
                                Text("Delete Account")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(password.isEmpty || isDeleting)
                    .accessibilityLabel(isDeleting ? "Deleting account" : "Delete Account")
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .alert("Delete your account?", isPresented: $isConfirming) {
                Button("Delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your account and all your documents will be permanently deleted.")
            }
            .manageSubscriptionsSheet(isPresented: $isShowingManageSubscriptions)
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await authService.deleteAccount(password: password)
            dismiss()
            onDeleted()
        } catch let APIError.server(_, message) {
            errorMessage = message ?? "Something went wrong — please try again."
        } catch APIError.unauthorized {
            errorMessage = "Your session has expired — sign out, sign back in, and try again."
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }
}

#Preview {
    DeleteAccountView(onDeleted: {})
        .environment(StoreKitManager())
}

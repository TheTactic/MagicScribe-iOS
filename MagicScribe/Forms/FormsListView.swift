import SwiftUI

nonisolated enum FormEditorTarget: Hashable {
    case new
    case existing(Int)
}

struct FormsListView: View {
    let onSignOut: () -> Void

    @State private var forms: [FormSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var formPendingDelete: FormSummary?

    private let formsService = FormsService()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && forms.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if forms.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(forms) { form in
                            NavigationLink(value: FormEditorTarget.existing(form.id)) {
                                row(for: form)
                            }
                        }
                        .onDelete { indexSet in
                            if let index = indexSet.first {
                                formPendingDelete = forms[index]
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("My Forms")
            .navigationDestination(for: FormEditorTarget.self) { target in
                switch target {
                case .new:
                    FormEditorView(formId: nil, onSaved: { Task { await loadForms() } })
                case .existing(let id):
                    FormEditorView(formId: id, onSaved: { Task { await loadForms() } })
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: FormEditorTarget.new) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Sign Out", role: .destructive, action: onSignOut)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert(
                "Delete this form?",
                isPresented: Binding(
                    get: { formPendingDelete != nil },
                    set: { if !$0 { formPendingDelete = nil } }
                ),
                presenting: formPendingDelete
            ) { form in
                Button("Delete", role: .destructive) {
                    Task { await delete(form) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { form in
                Text("\"\(form.title)\" will be permanently deleted.")
            }
            .task { await loadForms() }
            .refreshable { await loadForms() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.magicBlue.opacity(0.6))
            Text("No forms yet")
                .font(.headline)
                .foregroundStyle(Color.magicNavy)
            Text("Build your first form to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            NavigationLink(value: FormEditorTarget.new) {
                Label("New Form", systemImage: "plus.square.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.magicBlue)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func row(for form: FormSummary) -> some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(Color.magicBlue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(form.title)
                    .font(.headline)
                    .foregroundStyle(Color.magicNavy)
                Text(form.isPublished == 1 ? "Published" : "Draft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func loadForms() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            forms = try await formsService.list()
        } catch let FormsServiceError.listFailed(message) {
            errorMessage = message
        } catch let APIError.server(_, message) {
            errorMessage = message ?? "Something went wrong — please try again."
        } catch APIError.unauthorized {
            errorMessage = "Not signed in — please log in again."
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }

    private func delete(_ form: FormSummary) async {
        formPendingDelete = nil
        do {
            try await formsService.delete(formId: form.id)
            forms.removeAll { $0.id == form.id }
        } catch {
            errorMessage = "Couldn't delete \"\(form.title)\" — try again."
        }
    }
}

#Preview {
    FormsListView(onSignOut: {})
}

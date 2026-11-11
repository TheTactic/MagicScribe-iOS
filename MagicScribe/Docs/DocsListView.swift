import SwiftUI

nonisolated enum DocEditorTarget: Hashable {
    case new
    case existing(Int)
}

struct DocsListView: View {
    let onSignOut: () -> Void

    @State private var docs: [DocSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var docPendingDelete: DocSummary?

    private let docsService = DocsService()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && docs.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if docs.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(docs) { doc in
                            NavigationLink(value: DocEditorTarget.existing(doc.id)) {
                                row(for: doc)
                            }
                        }
                        .onDelete { indexSet in
                            if let index = indexSet.first {
                                docPendingDelete = docs[index]
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("My Docs")
            .navigationDestination(for: DocEditorTarget.self) { target in
                switch target {
                case .new:
                    DocsEditorView(docId: nil, onSaved: { Task { await loadDocs() } })
                case .existing(let id):
                    DocsEditorView(docId: id, onSaved: { Task { await loadDocs() } })
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: DocEditorTarget.new) {
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
                "Delete this document?",
                isPresented: Binding(
                    get: { docPendingDelete != nil },
                    set: { if !$0 { docPendingDelete = nil } }
                ),
                presenting: docPendingDelete
            ) { doc in
                Button("Delete", role: .destructive) {
                    Task { await delete(doc) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { doc in
                Text("\"\(doc.title)\" will be permanently deleted.")
            }
            .task { await loadDocs() }
            .refreshable { await loadDocs() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.magicBlue.opacity(0.6))
            Text("No documents yet")
                .font(.headline)
                .foregroundStyle(Color.magicNavy)
            Text("Dictate your first document to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            NavigationLink(value: DocEditorTarget.new) {
                Label("New Document", systemImage: "plus.square.fill")
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

    private func row(for doc: DocSummary) -> some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(Color.magicBlue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title)
                    .font(.headline)
                    .foregroundStyle(Color.magicNavy)
                Text(doc.updatedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func loadDocs() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            docs = try await docsService.list()
        } catch let DocsServiceError.listFailed(message) {
            errorMessage = message
        } catch let APIError.server(_, message) {
            errorMessage = message ?? "Something went wrong — please try again."
        } catch APIError.unauthorized {
            errorMessage = "Not signed in — please log in again."
        } catch {
            errorMessage = "Couldn't reach the server — check your connection and try again."
        }
    }

    private func delete(_ doc: DocSummary) async {
        docPendingDelete = nil
        do {
            try await docsService.delete(docId: doc.id)
            docs.removeAll { $0.id == doc.id }
        } catch {
            errorMessage = "Couldn't delete \"\(doc.title)\" — try again."
        }
    }
}

#Preview {
    DocsListView(onSignOut: {})
}

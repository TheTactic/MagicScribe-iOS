import Foundation

nonisolated enum DocsServiceError: Error {
    case saveFailed(String)
    case loadFailed(String)
    case listFailed(String)
    case deleteFailed(String)
    case voiceEditFailed(String)
    case upgradeRequired(String)
}

/// Wraps api/docs.php's list/load/save/delete actions. `load` collapses
/// any pre-existing multi-page document into one AttributedString (keeping
/// the first page's id as the sole kept id) — a document edited on web
/// before this feature shipped may already have 2+ real `document_pages`
/// rows, and loading only the first would silently truncate real content.
/// `save` always writes back as a single page with `full_sync: true`,
/// which is what performs that collapse server-side the first time a
/// multi-page doc is touched on iOS — an accepted, one-time, stated v1
/// behavior (see plan), not a bug.
final class DocsService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func list() async throws -> [DocSummary] {
        let response: DocsListResponse = try await client.get(
            .docs,
            queryItems: [URLQueryItem(name: "action", value: "list")],
            authenticated: true
        )
        guard response.success, let docs = response.docs else {
            throw DocsServiceError.listFailed(response.error ?? "Couldn't load your documents.")
        }
        return docs
    }

    /// Falls back to the legacy single `content_html` blob for a doc never
    /// migrated to per-page storage. `keptPageId` is `nil` for that legacy
    /// path (a fresh UUID gets assigned on next save) or the collapse
    /// target id for an already-paginated document.
    func load(docId: Int) async throws -> (title: String, text: AttributedString, keptPageId: String?) {
        let response: DocsLoadResponse = try await client.get(
            .docs,
            queryItems: [
                URLQueryItem(name: "action", value: "load"),
                URLQueryItem(name: "id", value: String(docId)),
            ],
            authenticated: true
        )
        guard response.success, let doc = response.doc else {
            throw DocsServiceError.loadFailed(response.error ?? "Couldn't load this document.")
        }

        if let pages = doc.pages, !pages.isEmpty {
            let combinedHTML = pages.map(\.contentHtml).joined()
            return (doc.title, DocHTMLBridge.parse(html: combinedHTML), pages.first?.id)
        } else {
            return (doc.title, DocHTMLBridge.parse(html: doc.contentHtml ?? ""), nil)
        }
    }

    /// Always writes back as exactly one page with `full_sync: true`.
    /// Returns the doc's id (new or existing) and whether the server
    /// flagged a resync — a concurrent edit from elsewhere (web, or
    /// another device) landed since this doc was last loaded here, so the
    /// caller should reload and confirm with the user before trusting any
    /// further local edit.
    func save(
        docId: Int?,
        title: String,
        text: AttributedString,
        keptPageId: String?
    ) async throws -> (docId: Int, resyncNeeded: Bool) {
        let pageId = keptPageId ?? UUID().uuidString
        let page = DocPageUpsert(id: pageId, orderKey: 1000, contentHtml: DocHTMLBridge.render(text))
        let request = DocsSaveRequest(
            action: "save",
            docId: docId,
            title: title,
            pages: [page],
            deletedPageIds: [],
            totalPages: 1,
            fullSync: true
        )
        let response: DocsSaveResponse = try await client.post(.docs, body: request, authenticated: true)
        guard response.success, let savedId = response.docId?.intValue else {
            throw DocsServiceError.saveFailed(response.error ?? "Couldn't save this document.")
        }
        return (savedId, response.resyncNeeded ?? false)
    }

    func delete(docId: Int) async throws {
        let request = DocsDeleteRequest(action: "delete", docId: docId)
        let response: SimpleSuccessResponse = try await client.post(.docs, body: request, authenticated: true)
        guard response.success else {
            throw DocsServiceError.deleteFailed("Couldn't delete this document.")
        }
    }

    /// Sends a spoken instruction + the document's current paragraph
    /// chunks to api/edit.php, which asks Claude to turn it into one or
    /// more structured edit operations. Gated server-side by the
    /// docs_voice_editing plan cap (Voice Pro+) — a 402 there is thrown by
    /// APIClient.send() as APIError.server before the body ever reaches
    /// EditResponse's decoder, so that's caught here, not checked on
    /// `response.upgrade`.
    func requestVoiceEdit(instruction: String, chunks: [EditChunk]) async throws -> [EditOperation] {
        let request = EditRequest(instruction: instruction, chunks: chunks)
        do {
            let response: EditResponse = try await client.post(.editDoc, body: request, authenticated: true)
            guard response.success, let operations = response.operations else {
                throw DocsServiceError.voiceEditFailed(response.error ?? "Couldn't understand that edit.")
            }
            return operations
        } catch let APIError.server(status, message) where status == 402 {
            throw DocsServiceError.upgradeRequired(
                message ?? "Voice editing isn't included in your plan. Upgrade to Voice Pro."
            )
        }
    }
}

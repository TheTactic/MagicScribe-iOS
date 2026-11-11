import Foundation

// MARK: - api/docs.php request/response wire types

nonisolated struct DocSummary: Decodable, Identifiable {
    let id: Int
    let title: String
    let updatedAt: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case id, title, source
        case updatedAt = "updated_at"
    }
}

nonisolated struct DocsListResponse: Decodable {
    let success: Bool
    let docs: [DocSummary]?
    let error: String?
}

/// A page as returned by `load` — no `order_key` in the response; array
/// order IS the order. `order_key` only appears in the outbound `save`
/// payload (see DocPageUpsert), assigned client-side.
nonisolated struct DocPage: Decodable, Identifiable {
    let id: String
    let contentHtml: String

    enum CodingKeys: String, CodingKey {
        case id
        case contentHtml = "content_html"
    }
}

/// `contentHtml`/`pages` are both optional and mutually exclusive — `pages`
/// is present once a document has been migrated to per-page storage;
/// `contentHtml` is the legacy single-blob fallback for a doc never touched
/// since that migration. DocsService.load collapses either shape into one
/// `AttributedString` via DocHTMLBridge.
nonisolated struct DocDetail: Decodable {
    let id: Int
    let title: String
    let contentHtml: String?
    let pages: [DocPage]?

    enum CodingKeys: String, CodingKey {
        case id, title, pages
        case contentHtml = "content_html"
    }
}

nonisolated struct DocsLoadResponse: Decodable {
    let success: Bool
    let doc: DocDetail?
    let error: String?
}

/// Outbound page shape for `save` — includes `order_key`, which `load`
/// never returns (client-assigned, purely a persistence-ordering key). v1
/// only ever sends exactly one page — see DocsService.save.
nonisolated struct DocPageUpsert: Encodable {
    let id: String
    let orderKey: Int
    let contentHtml: String

    enum CodingKeys: String, CodingKey {
        case id
        case orderKey = "order_key"
        case contentHtml = "content_html"
    }
}

nonisolated struct DocsSaveRequest: Encodable {
    let action: String
    let docId: Int?
    let title: String
    let pages: [DocPageUpsert]
    let deletedPageIds: [String]
    let totalPages: Int
    let fullSync: Bool

    enum CodingKeys: String, CodingKey {
        case action, title, pages
        case docId = "doc_id"
        case deletedPageIds = "deleted_page_ids"
        case totalPages = "total_pages"
        case fullSync = "full_sync"
    }
}

/// `doc_id` uses the same insert-string/update-number PHP idiom confirmed
/// on `forms.php` — see `FlexibleId` (Models/FormModels.swift). Don't assume
/// a plain `Int` decodes cleanly here without the same guard.
nonisolated struct DocsSaveResponse: Decodable {
    let success: Bool
    let docId: FlexibleId?
    let resyncNeeded: Bool?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, error
        case docId = "doc_id"
        case resyncNeeded = "resync_needed"
    }
}

nonisolated struct DocsDeleteRequest: Encodable {
    let action: String
    let docId: Int

    enum CodingKeys: String, CodingKey {
        case action
        case docId = "doc_id"
    }
}

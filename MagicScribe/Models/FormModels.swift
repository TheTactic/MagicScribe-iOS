import Foundation

// MARK: - .msf wire format

/// Dedicated encoder/decoder for the .msf JSON blob (api/forms.php's
/// `msf_data` column, sent/received as a plain string nested inside the
/// outer request/response). Scoped separately from APIClient's shared JSON
/// coders because the real web builder (assets/js/builder.js) has zero
/// tolerance for a missing or misnamed field key — its renderer crashes
/// with no null-check — so this uses snake_case key conversion instead of
/// ~20 hand-written CodingKeys to remove that typo risk entirely. Swift
/// property names use single-capital Id/Url spelling throughout so
/// convertToSnakeCase/FromSnakeCase stays unambiguous.
enum FormsJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

nonisolated struct MSFForm: Codable {
    var msfVersion: String
    var meta: MSFMeta
    var pages: [MSFPage]
    var formAiContext: String
    var answerTemplates: [String]
    var permissions: MSFPermissions
    var audit: MSFAudit

    /// A brand-new, empty form. `meta.createdBy` is a harmless literal —
    /// it's write-only from the builder's own load path (never read back);
    /// real ownership is derived server-side from the auth token/session.
    static func blank(title: String) -> MSFForm {
        let now = ISO8601DateFormatter().string(from: Date())
        return MSFForm(
            msfVersion: "1.2",
            meta: MSFMeta(
                title: title, createdBy: 0, createdAt: now, modifiedAt: now,
                backgroundColor: "#ffffff", dimensions: MSFMetaDimensions(width: 800, height: 1100)
            ),
            pages: [],
            formAiContext: "",
            answerTemplates: [],
            permissions: .default,
            audit: .default
        )
    }
}

nonisolated struct MSFMeta: Codable {
    var title: String
    var createdBy: Int
    var createdAt: String
    var modifiedAt: String
    var backgroundColor: String
    var dimensions: MSFMetaDimensions
}

nonisolated struct MSFMetaDimensions: Codable {
    var width: Int
    var height: Int
}

/// A normal page has only id/label/fields — builder.js never writes a
/// "type" key on a page it creates. ("background"-type pages are a
/// separate, backend-seeded scanned-template variant already excluded from
/// api/forms.php's `list` action, so this app should never encounter one.)
nonisolated struct MSFPage: Codable, Identifiable {
    var id: String
    var label: String
    var fields: [MSFField]
}

nonisolated struct MSFField: Codable, Identifiable {
    var id: String
    var type: String
    var label: String
    var machineName: String
    var aiContext: String
    var placeholder: String
    var required: Bool
    // Conditional, type-specific keys — Optional so Swift's synthesized
    // Encodable omits the key entirely when nil, matching builder.js's
    // "key doesn't exist for this type" semantics exactly.
    var dateFormat: String?
    var options: [String]?
    var isSectionHeader: Bool?
    var src: String?
    var objectFit: String?
    var allowUserUpload: Bool?
    var contextChain: MSFContextChain?
    // Non-optional — always present, matching the web's crash-on-missing
    // behavior. FormLayoutEngine.makeField always populates a placeholder
    // value even before the real layout pass runs.
    var position: MSFFieldPosition
    var dimensions: MSFFieldDimensions
    var style: MSFFieldStyle
}

nonisolated struct MSFContextChain: Codable {
    var sectionId: String?
    var groupId: String?
    var role: String
}

nonisolated struct MSFFieldPosition: Codable {
    var x: Double
    var y: Double
}

nonisolated struct MSFFieldDimensions: Codable {
    var w: Double
    var h: Double
}

nonisolated struct MSFFieldStyle: Codable {
    var fontFamily: String
    var fontSize: Int
    var fontColor: String
    var backgroundColor: String
    var borderColor: String
    var bold: Bool
    var italic: Bool

    static let `default` = MSFFieldStyle(
        fontFamily: "Arial", fontSize: 14, fontColor: "#333333",
        backgroundColor: "#ffffff", borderColor: "#cccccc", bold: false, italic: false
    )
}

nonisolated struct MSFPermissions: Codable {
    var allowVoiceFill: Bool
    var allowManualFill: Bool
    var fieldsLockedAfterSign: Bool

    static let `default` = MSFPermissions(allowVoiceFill: true, allowManualFill: true, fieldsLockedAfterSign: true)
}

nonisolated struct MSFAudit: Codable {
    var filledBy: Int?
    var filledAt: String?
    var ipAddress: String?
    var signatureValid: Bool

    static let `default` = MSFAudit(filledBy: nil, filledAt: nil, ipAddress: nil, signatureValid: false)
}

// MARK: - api/forms.php request/response wire types

nonisolated struct FormsListRequest: Encodable {
    let action: String
}

/// api/forms.php's `list` row shape — confirmed via live testing that `id`
/// comes back as a JSON number here (unlike `save`'s `form_id`, which is a
/// JSON string — see FormsSaveResponse).
nonisolated struct FormSummary: Decodable, Identifiable {
    let id: Int
    let title: String
    let isPublished: Int
    let createdAt: String
    let modifiedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case isPublished = "is_published"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }
}

nonisolated struct FormsListResponse: Decodable {
    let success: Bool
    let forms: [FormSummary]?
    let error: String?
}

nonisolated struct FormsSaveRequest: Encodable {
    let action: String
    let title: String
    let msfData: String
    let formId: Int?

    enum CodingKeys: String, CodingKey {
        case action, title
        case msfData = "msf_data"
        case formId = "form_id"
    }
}

/// api/forms.php's `save` action returns `form_id` as a JSON STRING on
/// insert (PHP's lastInsertId()) but a JSON NUMBER on update (intval()) —
/// confirmed by direct testing against both code paths, not a guess. This
/// decodes either.
nonisolated enum FlexibleFormId: Decodable {
    case int(Int)
    case string(String)

    var intValue: Int? {
        switch self {
        case .int(let value): value
        case .string(let value): Int(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}

nonisolated struct FormsSaveResponse: Decodable {
    let success: Bool
    let formId: FlexibleFormId?
    let error: String?
    let upgrade: Bool?
    let message: String?
    let upgradeUrl: String?

    var formIdInt: Int? { formId?.intValue }

    enum CodingKeys: String, CodingKey {
        case success, error, upgrade, message
        case formId = "form_id"
        case upgradeUrl = "upgrade_url"
    }
}

nonisolated struct FormsLoadRequest: Encodable {
    let action: String
    let formId: Int

    enum CodingKeys: String, CodingKey {
        case action
        case formId = "form_id"
    }
}

nonisolated struct FormDetail: Decodable {
    let id: Int
    let title: String
    let msfData: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case msfData = "msf_data"
    }
}

nonisolated struct FormsLoadResponse: Decodable {
    let success: Bool
    let form: FormDetail?
    let error: String?
}

nonisolated struct FormsDeleteRequest: Encodable {
    let action: String
    let formId: Int

    enum CodingKeys: String, CodingKey {
        case action
        case formId = "form_id"
    }
}

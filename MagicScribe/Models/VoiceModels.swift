import Foundation

/// Minimal subset of the real .msf field schema — just enough to describe
/// one field for api/ai.php's map_fields prompt (id, label, type, options).
nonisolated struct FormFieldDescriptor: Encodable {
    let id: String
    let label: String
    let type: String
    let options: [String]?

    init(id: String, label: String, type: String, options: [String]? = nil) {
        self.id = id
        self.label = label
        self.type = type
        self.options = options
    }
}

/// api/speech.php's response shape. Only `success`/`upgrade`-style errors set
/// a real HTTP status code — most error cases are 200 with `success: false`,
/// so this must always decode; callers check `.success` themselves.
nonisolated struct TranscribeResponse: Decodable {
    let success: Bool
    let transcript: String?
    let error: String?
}

nonisolated struct MapFieldsRequest: Encodable {
    let action: String
    let transcript: String
    let fields: [FormFieldDescriptor]
    let context: String
}

/// api/ai.php's map_fields response shape — same "always decodes, check
/// .success" reasoning as TranscribeResponse.
nonisolated struct MapFieldsResponse: Decodable {
    let success: Bool
    let mapping: [String: String?]?
    let error: String?
}

nonisolated struct BuildFormRequest: Encodable {
    let action: String
    let description: String
    let context: String
}

/// One field from api/ai.php's build_form response — Claude's flat
/// intermediate shape (type/label/placeholder/required/ai_context/options),
/// not a full MSF field (no id/machine_name/position/context_chain — the
/// real client assembles those; this demo only displays the result).
nonisolated struct BuiltFieldDescriptor: Decodable {
    let type: String
    let label: String
    let placeholder: String
    let required: Bool
    let aiContext: String
    let options: [String]?

    enum CodingKeys: String, CodingKey {
        case type, label, placeholder, required, options
        case aiContext = "ai_context"
    }
}

/// api/ai.php's build_form response shape — same "always decodes, check
/// .success" reasoning as the other response types.
nonisolated struct BuildFormResponse: Decodable {
    let success: Bool
    let formTitle: String?
    let formAiContext: String?
    let fields: [BuiltFieldDescriptor]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, fields, error
        case formTitle = "form_title"
        case formAiContext = "form_ai_context"
    }
}

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

/// One addressable unit api/edit.php's Claude prompt can target — web's
/// `.dictated-chunk` elements don't exist in this single-page iOS model, so
/// this maps onto the "\n"-delimited paragraphs already produced by
/// DocHTMLBridge, numbered 1-based to match the prompt's "Line N" framing.
nonisolated struct EditChunk: Encodable {
    let id: Int
    let text: String
}

nonisolated struct EditRequest: Encodable {
    let instruction: String
    let chunks: [EditChunk]
    /// Only set during onboarding ("ios_onboarding_demo_docs") — bypasses
    /// the docs_voice_editing plan gate server-side. nil for every real
    /// app call; Swift's auto-synthesized Encodable uses encodeIfPresent
    /// for Optional properties, so nil omits the key entirely rather than
    /// encoding `"context":null`, matching the request shape before this
    /// field existed.
    let context: String?
}

/// One operation Claude returned from api/edit.php — `chunk`/`target`/
/// `replacement`/`format` are each only present for the operation types
/// that use them (see DocVoiceEditExecutor.apply(_:to:)).
nonisolated struct EditOperation: Decodable {
    let type: String
    let chunk: Int?
    let target: String?
    let replacement: String?
    let format: String?
}

/// api/edit.php's response shape. Its 402 upgrade-required path always
/// sets a non-2xx HTTP status, which APIClient.send() intercepts as
/// APIError.server before this ever gets decoded — see
/// DocsService.requestVoiceEdit(), which catches that instead.
nonisolated struct EditResponse: Decodable {
    let success: Bool
    let operations: [EditOperation]?
    let error: String?
}

/// api/refine.php's request shape — a plain-dictation chunk (no magic
/// commands) plus the session's running context and the previously
/// inserted chunk, so Claude can fix mishears and correct a word split
/// across the chunk boundary.
nonisolated struct RefineRequest: Encodable {
    let transcript: String
    let context: String
    let prevChunk: String
    /// Only set during onboarding ("ios_onboarding_demo_docs") — bypasses
    /// the verified-email requirement server-side. A separate field from
    /// `context` above (that one is the running document text used as
    /// Claude's correction context, not a bypass marker) — nil for every
    /// real app call, omitted entirely rather than encoding `null`, same
    /// convention as `EditRequest.context`.
    let demoContext: String?

    enum CodingKeys: String, CodingKey {
        case transcript, context
        case prevChunk = "prev_chunk"
        case demoContext = "demo_context"
    }
}

/// Always a normal 200, even when the docs_minutes cap is hit — that
/// branch is a soft, non-blocking "here's your transcript back unchanged"
/// response (`upgrade: true`), not a thrown error like Voice Edit's 402.
/// `refined`/`prevFix` are nil only on a genuine request failure the
/// caller should treat as "proceed with the raw transcript."
nonisolated struct RefineResponse: Decodable {
    let success: Bool
    let refined: String?
    let prevFix: String?
    let upgrade: Bool?
    let message: String?
    let upgradeUrl: String?

    enum CodingKeys: String, CodingKey {
        case success, refined, upgrade, message
        case prevFix = "prev_fix"
        case upgradeUrl = "upgrade_url"
    }
}

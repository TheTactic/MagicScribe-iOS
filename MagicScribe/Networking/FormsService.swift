import Foundation

nonisolated enum FormsServiceError: Error {
    case limitReached(message: String, upgradeUrl: String?)
    case saveFailed(String)
    case loadFailed(String)
    case listFailed(String)
    case deleteFailed(String)
}

/// Wraps api/forms.php's save/list/load/delete actions. The .msf blob
/// itself is a string nested inside the outer JSON, encoded/decoded through
/// FormsJSON's dedicated snake_case coder (Models/FormModels.swift) — kept
/// separate from the outer request/response JSON, which uses APIClient's
/// default hand-written-CodingKeys coder.
final class FormsService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func list() async throws -> [FormSummary] {
        let request = FormsListRequest(action: "list")
        let response: FormsListResponse = try await client.post(.forms, body: request, authenticated: true)
        guard response.success, let forms = response.forms else {
            throw FormsServiceError.listFailed(response.error ?? "Couldn't load your forms.")
        }
        return forms
    }

    /// Takes the editor's flat, single-list field model (no page UI — see
    /// FormEditorView), runs the real single-column layout pass
    /// (FormLayoutEngine.layoutSingleColumn), and re-buckets into pages
    /// before saving — so the saved .msf always has valid position/
    /// dimensions and stays safely openable in the web builder.
    /// `baseForm` carries through everything else (msfVersion/formAiContext/
    /// answerTemplates/permissions/audit) — its own `pages` are discarded in
    /// favor of the freshly-laid-out ones. Returns the form's id (new or
    /// existing).
    func save(title: String, fields: [MSFField], baseForm: MSFForm, formId: Int?) async throws -> Int {
        var form = baseForm
        let buckets = FormLayoutEngine.layoutSingleColumn(fields: fields)
        form.pages = buckets.enumerated().map { index, pageFields in
            MSFPage(id: "page_\(index + 1)", label: "Page \(index + 1)", fields: pageFields)
        }
        form.meta.title = title
        form.meta.modifiedAt = ISO8601DateFormatter().string(from: Date())

        let msfData = String(decoding: try FormsJSON.encoder.encode(form), as: UTF8.self)
        let request = FormsSaveRequest(action: "save", title: title, msfData: msfData, formId: formId)
        let response: FormsSaveResponse = try await client.post(.forms, body: request, authenticated: true)

        guard response.success else {
            if response.error == "form_limit_reached" {
                throw FormsServiceError.limitReached(
                    message: response.message ?? "You've reached your form limit.",
                    upgradeUrl: response.upgradeUrl
                )
            }
            throw FormsServiceError.saveFailed(response.message ?? response.error ?? "Couldn't save this form.")
        }
        guard let savedId = response.formIdInt ?? formId else {
            throw FormsServiceError.saveFailed("Didn't get a form id back from the server.")
        }
        return savedId
    }

    func load(formId: Int) async throws -> (title: String, form: MSFForm) {
        let request = FormsLoadRequest(action: "load", formId: formId)
        let response: FormsLoadResponse = try await client.post(.forms, body: request, authenticated: true)
        guard response.success, let detail = response.form else {
            throw FormsServiceError.loadFailed(response.error ?? "Couldn't load this form.")
        }
        let form = try FormsJSON.decoder.decode(MSFForm.self, from: Data(detail.msfData.utf8))
        return (detail.title, form)
    }

    func delete(formId: Int) async throws {
        let request = FormsDeleteRequest(action: "delete", formId: formId)
        let response: SimpleSuccessResponse = try await client.post(.forms, body: request, authenticated: true)
        guard response.success else {
            throw FormsServiceError.deleteFailed("Couldn't delete this form.")
        }
    }
}

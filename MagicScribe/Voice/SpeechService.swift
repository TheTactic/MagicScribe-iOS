import Foundation

nonisolated enum SpeechServiceError: Error {
    case transcriptionFailed(String)
    case mappingFailed(String)
    case buildFailed(String)
}

/// Standalone, reusable — not onboarding-specific. Wraps the two real backend
/// calls the web Filler already makes: Whisper transcription (api/speech.php)
/// and Claude-based field mapping (api/ai.php, action: map_fields).
final class SpeechService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    func transcribe(fileURL: URL, language: String = "en", context: String = "filler") async throws -> String {
        let fileData = try Data(contentsOf: fileURL)
        let response: TranscribeResponse = try await client.postMultipart(
            .speech,
            fileFieldName: "audio",
            fileName: "recording.m4a",
            mimeType: "audio/m4a",
            fileData: fileData,
            formFields: ["language": language, "context": context],
            authenticated: true
        )
        guard response.success, let transcript = response.transcript else {
            throw SpeechServiceError.transcriptionFailed(response.error ?? "Transcription failed.")
        }
        return transcript
    }

    func mapFields(transcript: String, fields: [FormFieldDescriptor], context: String = "filler") async throws -> [String: String?] {
        let request = MapFieldsRequest(action: "map_fields", transcript: transcript, fields: fields, context: context)
        let response: MapFieldsResponse = try await client.post(.mapFields, body: request, authenticated: true)
        guard response.success, let mapping = response.mapping else {
            throw SpeechServiceError.mappingFailed(response.error ?? "Field mapping failed.")
        }
        return mapping
    }

    func buildForm(description: String, context: String = "ios_onboarding_demo_build") async throws -> BuildFormResponse {
        let request = BuildFormRequest(action: "build_form", description: description, context: context)
        let response: BuildFormResponse = try await client.post(.buildForm, body: request, authenticated: true)
        guard response.success, response.fields != nil else {
            throw SpeechServiceError.buildFailed(response.error ?? "Form building failed.")
        }
        return response
    }
}

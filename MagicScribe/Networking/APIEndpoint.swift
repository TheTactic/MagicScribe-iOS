import Foundation

nonisolated enum APIEndpoint {
    case authToken
    case registerToken
    case verifyEmailCode
    case resendVerificationCode
    case recoverVerification
    case speech
    case mapFields
    case buildForm
    case forms

    var path: String {
        switch self {
        case .authToken: "/api/auth_token.php"
        case .registerToken: "/api/register_token.php"
        case .verifyEmailCode: "/api/verify_email_code.php"
        case .resendVerificationCode: "/api/resend_verification_code.php"
        case .recoverVerification: "/api/recover_verification.php"
        case .speech: "/api/speech.php"
        case .mapFields: "/api/ai.php"
        case .buildForm: "/api/ai.php"
        case .forms: "/api/forms.php"
        }
    }
}

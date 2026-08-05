import Foundation

/// Domain errors for Cash Flow.
///
/// ## Presentation law
/// 1. Throw `CashFlowError` from CashFlowData (never bare `NSError` / opaque codes).
/// 2. Every case has a non-empty `errorDescription` fit for UI banners/alerts.
/// 3. Feature code displays errors **only** via
///    `CashFlowError.userFacingMessage(for:fallback:)` — never invent parallel mappers
///    and never show raw `"CashFlowKit.CashFlowError error N"` strings.
/// 4. `fallback` is used only when the error is not a `CashFlowError` and has no
///    usable localized description (e.g. cancellation edge cases).
/// 5. Foundation Models–specific mapping stays in CashFlowData; it must finish by
///    throwing `CashFlowError.intelligence(message:)` (or `.intelligenceUnavailable`).
public enum CashFlowError: Error, Sendable, Equatable {
    case unauthorized
    case paymentRequired
    case transport(message: String)
    case decoding(message: String)
    case persistence(message: String)
    case providerMessages([String])
    case notLinked
    case cancelled
    case authenticationUnavailable
    case authenticationFailed
    /// On-device Foundation Models / Apple Intelligence is not usable.
    case intelligenceUnavailable
    case intelligence(message: String)
}

extension CashFlowError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authorization failed. Create a new SimpleFIN token and try again."
        case .paymentRequired:
            return "SimpleFIN requires an active subscription."
        case .transport(let message):
            return Self.nonEmpty(message, fallback: "A network error occurred.")
        case .decoding(let message):
            return Self.nonEmpty(message, fallback: "Couldn't read the server response.")
        case .persistence(let message):
            return Self.nonEmpty(message, fallback: "Couldn't save data.")
        case .providerMessages(let messages):
            let joined = messages
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return Self.nonEmpty(joined, fallback: "The provider reported a problem.")
        case .notLinked:
            return "No account is linked."
        case .cancelled:
            return "Cancelled."
        case .authenticationUnavailable:
            return "Device authentication is unavailable. Set a passcode in Settings."
        case .authenticationFailed:
            return "Authentication failed. Try again."
        case .intelligenceUnavailable:
            return "On-device intelligence isn’t available."
        case .intelligence(let message):
            return Self.nonEmpty(message, fallback: "On-device generation failed.")
        }
    }

    /// Single UI entry point for any thrown `Error`.
    public static func userFacingMessage(for error: Error, fallback: String) -> String {
        if let cashFlow = fromBridgedError(error) {
            return cashFlow.errorDescription ?? fallback
        }
        if error is CancellationError {
            return fallback
        }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || looksLikeOpaqueTypeDump(text) {
            return fallback
        }
        return text
    }

    /// Recovers a typed error after Foundation Models / ObjC bridging strips the enum.
    public static func fromBridgedError(_ error: Error) -> CashFlowError? {
        if let typed = error as? CashFlowError {
            return typed
        }
        let nsError = error as NSError
        guard nsError.domain == errorDomain || nsError.domain.contains("CashFlowError") else {
            return nil
        }
        let message = (nsError.userInfo[messageUserInfoKey] as? String)
            ?? (nsError.userInfo[NSLocalizedDescriptionKey] as? String)
            ?? ""
        switch nsError.code {
        case 0: return .unauthorized
        case 1: return .paymentRequired
        case 2: return .transport(message: message)
        case 3: return .decoding(message: message)
        case 4: return .persistence(message: message)
        case 5:
            let messages = (nsError.userInfo[messagesUserInfoKey] as? [String]) ?? [message]
            return .providerMessages(messages)
        case 6: return .notLinked
        case 7: return .cancelled
        case 8: return .authenticationUnavailable
        case 9: return .authenticationFailed
        case 10: return .intelligenceUnavailable
        case 11: return .intelligence(message: message)
        default: return nil
        }
    }

    private static let messageUserInfoKey = "CashFlowError.message"
    private static let messagesUserInfoKey = "CashFlowError.messages"

    private static func nonEmpty(_ message: String, fallback: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func looksLikeOpaqueTypeDump(_ text: String) -> Bool {
        text.contains("CashFlowError")
            || text.contains("GenerationError")
            || text.range(of: #"\berror -?\d+\b"#, options: .regularExpression) != nil
    }
}

extension CashFlowError: CustomNSError {
    public static var errorDomain: String { "CashFlowKit.CashFlowError" }

    public var errorCode: Int {
        switch self {
        case .unauthorized: return 0
        case .paymentRequired: return 1
        case .transport: return 2
        case .decoding: return 3
        case .persistence: return 4
        case .providerMessages: return 5
        case .notLinked: return 6
        case .cancelled: return 7
        case .authenticationUnavailable: return 8
        case .authenticationFailed: return 9
        case .intelligenceUnavailable: return 10
        case .intelligence: return 11
        }
    }

    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [:]
        if let description = errorDescription {
            info[NSLocalizedDescriptionKey] = description
        }
        switch self {
        case .transport(let message),
             .decoding(let message),
             .persistence(let message),
             .intelligence(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                info[Self.messageUserInfoKey] = trimmed
            }
        case .providerMessages(let messages):
            info[Self.messagesUserInfoKey] = messages
        default:
            break
        }
        return info
    }
}

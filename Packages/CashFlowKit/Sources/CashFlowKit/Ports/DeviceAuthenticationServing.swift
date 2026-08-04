import Foundation

/// System biometrics / device passcode gate (LocalAuthentication behind the data layer).
public protocol DeviceAuthenticationServing: Sendable {
    /// Whether the device can present owner authentication (passcode and/or biometrics).
    var canAuthenticate: Bool { get }

    /// User-facing label: "Face ID", "Touch ID", "Optic ID", or "Passcode".
    var biometryDisplayName: String { get }

    /// Prompts the user. Throws `CashFlowError.cancelled` on user/system cancel,
    /// `CashFlowError.authenticationFailed` on failure, `CashFlowError.authenticationUnavailable` when policy cannot run.
    func authenticate(reason: String) async throws
}

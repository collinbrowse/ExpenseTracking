import Foundation
import LocalAuthentication
import CashFlowKit

public struct LocalAuthenticationDeviceAuthenticator: DeviceAuthenticationServing, Sendable {
    public init() {}

    public var canAuthenticate: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public var biometryDisplayName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Passcode"
        @unknown default:
            return "Passcode"
        }
    }

    public func authenticate(reason: String) async throws {
        let context = LAContext()
        var evaluateError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluateError) else {
            throw CashFlowError.authenticationUnavailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            guard success else {
                throw CashFlowError.authenticationFailed
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                throw CashFlowError.cancelled
            case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled:
                throw CashFlowError.authenticationUnavailable
            default:
                throw CashFlowError.authenticationFailed
            }
        } catch let error as CashFlowError {
            throw error
        } catch {
            throw CashFlowError.authenticationFailed
        }
    }
}

import Foundation

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
}

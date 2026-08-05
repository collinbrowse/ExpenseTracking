import Foundation

/// Optional on-device category suggestion. `nil` means no opinion (keep resolve / keyword path).
public protocol TransactionCategoryEnriching: Sendable {
    func suggestCategory(description: String, amount: Decimal) async -> CategoryID?
}

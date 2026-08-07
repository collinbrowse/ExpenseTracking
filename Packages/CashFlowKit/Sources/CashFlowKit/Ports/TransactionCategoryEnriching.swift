import Foundation

/// Optional on-device category suggestion. `nil` means no opinion (keyword fallback applies).
public protocol TransactionCategoryEnriching: Sendable {
    func suggestCategory(_ request: CategorySuggestionRequest) async -> CategoryID?
}

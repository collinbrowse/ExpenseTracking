import Foundation
import CashFlowKit

/// Returns an LLM category only when Apple Intelligence is available; otherwise `nil`.
public struct CompositeTransactionCategoryEnricher: TransactionCategoryEnriching {
    private let availability: any OnDeviceModelAvailabilityChecking
    private let foundation: (any TransactionCategoryEnriching)?
    private let workCoordinator: FoundationModelsWorkCoordinator

    public init(
        availability: any OnDeviceModelAvailabilityChecking,
        foundation: (any TransactionCategoryEnriching)?,
        workCoordinator: FoundationModelsWorkCoordinator
    ) {
        self.availability = availability
        self.foundation = foundation
        self.workCoordinator = workCoordinator
    }

    public func suggestCategory(description: String, amount: Decimal) async -> CategoryID? {
        guard !(await workCoordinator.isAssetsUnavailable) else {
            return nil
        }
        guard await availability.availability() == .available, let foundation else {
            return nil
        }
        return await foundation.suggestCategory(description: description, amount: amount)
    }
}

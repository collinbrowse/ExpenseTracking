import Foundation
import CashFlowKit

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
@Generable
struct GenerableCategorySuggestion {
    @Guide(
        description: "Best matching system category display name",
        .anyOf([
            "Income",
            "Hidden",
            "Transfer",
            "Credit Card Payment",
            "Groceries",
            "Food & Dining",
            "Auto & Transport",
            "Shopping",
            "Bills & Utilities",
            "Entertainment",
            "Rent & Mortgage",
            "Travel & Vacation",
            "Health & Fitness",
            "Business Services",
            "Fees & Charges",
            "Medical",
            "Other",
        ])
    )
    var categoryName: String
}

@available(iOS 26, macOS 26, *)
public struct FoundationModelsCategoryEnricher: TransactionCategoryEnriching {
    public init() {}

    public func suggestCategory(description: String, amount: Decimal) async -> CategoryID? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let amountText = NSDecimalNumber(decimal: amount).stringValue
        do {
            return try await FoundationModelsWorkCoordinator.shared.runExclusive {
                let model = FoundationModelsWorkCoordinator.contentTransformationModel()
                let session = LanguageModelSession(
                    model: model,
                    instructions: """
                    Classify personal finance transactions into exactly one system category.
                    Prefer Other when unsure. Use Income only for clear payroll/paycheck credits.
                    Use Transfer or Credit Card Payment for money movement, not spending.
                    """
                )
                let response = try await session.respond(
                    to: """
                    Classify this transaction.
                    Description: \(trimmed)
                    Amount: \(amountText) (positive is credit/income, negative is debit/expense)
                    """,
                    generating: GenerableCategorySuggestion.self
                )
                let name = response.content.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                return SystemCategory.allCases.first { $0.name == name }?.id
            }
        } catch {
            return nil
        }
    }
}
#endif

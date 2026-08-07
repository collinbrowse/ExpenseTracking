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
    private let workCoordinator: FoundationModelsWorkCoordinator

    public init(workCoordinator: FoundationModelsWorkCoordinator) {
        self.workCoordinator = workCoordinator
    }

    public func suggestCategory(_ request: CategorySuggestionRequest) async -> CategoryID? {
        let raw = request.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = request.enrichedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty || !title.isEmpty else { return nil }

        let amountText = NSDecimalNumber(decimal: request.amount).stringValue
        let dateText = ISO8601DateFormatter().string(from: request.postedDate)
        let location = request.enrichedLocation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let account = request.accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let institution = request.institutionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        do {
            return try await workCoordinator.runExclusive {
                let model = FoundationModelsWorkCoordinator.contentTransformationModel()
                let session = LanguageModelSession(
                    model: model,
                    instructions: """
                    Classify personal finance transactions into exactly one system category.
                    Prefer Other when unsure. Use Income only for clear payroll/paycheck credits.
                    Use Transfer or Credit Card Payment for money movement, not spending.
                    Never use Undefined — that is only an unprocessed marker.
                    """
                )
                let response = try await session.respond(
                    to: """
                    Classify this transaction.
                    Bank description: \(raw)
                    Enriched title: \(title.isEmpty ? "(none)" : title)
                    Location: \(location.isEmpty ? "(none)" : location)
                    Amount: \(amountText) \(request.currencyCode) (positive is credit/income, negative is debit/expense)
                    Posted date: \(dateText)
                    Pending: \(request.isPending)
                    Account: \(account.isEmpty ? "(unknown)" : account)
                    Institution: \(institution.isEmpty ? "(unknown)" : institution)
                    """,
                    generating: GenerableCategorySuggestion.self
                )
                let name = response.content.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let match = SystemCategory.allCases.first(where: { $0.name == name }),
                      match != .undefined
                else { return nil }
                return match.id
            }
        } catch {
            return nil
        }
    }
}
#endif

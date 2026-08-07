import Foundation
import CashFlowKit

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
@Generable
struct MerchantLocationFields {
    @Guide(description: """
        Merchant or payee name only. Do not include city, state, ZIP, country, store numbers, \
        or bank padding. Never repeat words that belong in location.
        """)
    var title: String

    @Guide(description: """
        Geographic location only (city and state/region/country) when clearly present in the \
        text; otherwise empty string. Do not put the merchant name here.
        """)
    var location: String
}

@available(iOS 26, macOS 26, *)
public struct FoundationModelsDescriptionEnricher: TransactionDescriptionEnriching {
    private let workCoordinator: FoundationModelsWorkCoordinator

    public init(workCoordinator: FoundationModelsWorkCoordinator) {
        self.workCoordinator = workCoordinator
    }

    public func enrich(rawDescription: String) async -> ParsedTransactionDescription {
        let trimmed = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedTransactionDescription(title: "", location: nil, raw: "")
        }

        do {
            return try await workCoordinator.runExclusive {
                let model = FoundationModelsWorkCoordinator.contentTransformationModel()
                let session = LanguageModelSession(
                    model: model,
                    instructions: """
                    Split bank transaction descriptions into a merchant/payee title and an \
                    optional geographic location.
                    Rules:
                    - title = who was paid (or who paid), readable, without city/state/country.
                    - location = city and state (or region/country) only when those words appear \
                      in the description; otherwise empty.
                    - Never copy location words into title. Never invent geography.
                    - Drop store numbers, terminal IDs, and excess bank padding from title.
                    - Never return schema type names, property names, or placeholder tokens.
                    Examples:
                    - "TEQUILAS DURANGO CO" → title "Tequilas", location "Durango CO"
                    - "KROGER #412 FORT COLLINS CO" → title "Kroger", location "Fort Collins CO"
                    - "STARBUCKS STORE 12345 SEATTLE WA" → title "Starbucks", location "Seattle WA"
                    - "ACH PAYROLL ACME CORP" → title "ACH Payroll Acme Corp", location ""
                    - "AMERICAN EXPRESS CO" → title "American Express", location ""
                    """
                )
                let response = try await session.respond(
                    to: "Parse this transaction description into title and location:\n\(trimmed)",
                    generating: MerchantLocationFields.self
                )
                let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let location = response.content.location.trimmingCharacters(in: .whitespacesAndNewlines)
                if let validated = ValidateParsedDescriptionUseCase.execute(
                    title: title,
                    location: location.isEmpty ? nil : location,
                    rawDescription: trimmed
                ) {
                    return validated
                }
                return ParsedTransactionDescription(title: "", location: nil, raw: trimmed)
            }
        } catch {
            if FoundationModelsWorkCoordinator.isRateLimitedError(error) {
                await workCoordinator.noteRateLimited()
            }
            // Rate-limit retries already happened inside runExclusive. Remaining failures
            // (unsupported language, refused parse, etc.) leave the row raw — except rate
            // limits, which the coordinator will pause and retry without skipping.
            return ParsedTransactionDescription(title: "", location: nil, raw: trimmed)
        }
    }
}
#endif

import Foundation
import CashFlowKit

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
@Generable
struct GenerableMerchantParse {
    @Guide(description: "Clean merchant or payee name without location, store numbers, or bank codes")
    var title: String

    @Guide(description: "City, region, state, or country if present in the description; empty string if none")
    var location: String
}

@available(iOS 26, macOS 26, *)
public struct FoundationModelsDescriptionEnricher: TransactionDescriptionEnriching {
    public init() {}

    public func enrich(rawDescription: String) async -> ParsedTransactionDescription {
        let trimmed = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedTransactionDescription(title: "", location: nil, raw: "")
        }

        do {
            return try await FoundationModelsWorkCoordinator.shared.runExclusive {
                let model = FoundationModelsWorkCoordinator.contentTransformationModel()
                let session = LanguageModelSession(
                    model: model,
                    instructions: """
                    Extract merchant/payee names and locations from bank transaction descriptions.
                    Return a clean human-readable merchant title and any geographic location.
                    Do not invent a location that is not suggested by the text.
                    """
                )
                let response = try await session.respond(
                    to: "Parse this transaction description:\n\(trimmed)",
                    generating: GenerableMerchantParse.self
                )
                let title = response.content.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let location = response.content.location.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else {
                    return ParseTransactionDescriptionUseCase.execute(trimmed)
                }
                return ParsedTransactionDescription(
                    title: title,
                    location: location.isEmpty ? nil : location,
                    raw: trimmed
                )
            }
        } catch {
            return ParseTransactionDescriptionUseCase.execute(trimmed)
        }
    }
}
#endif

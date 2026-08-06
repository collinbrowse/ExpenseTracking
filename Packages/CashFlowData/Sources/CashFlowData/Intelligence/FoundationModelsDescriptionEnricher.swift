import Foundation
import CashFlowKit

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
@Generable
struct MerchantLocationFields {
    @Guide(description: "Clean merchant or payee name without location, store numbers, or bank codes")
    var title: String

    @Guide(description: "City, region, state, or country if present in the description; empty string if none")
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
                    Extract merchant/payee names and locations from bank transaction descriptions.
                    Return a clean human-readable merchant title and any geographic location.
                    Do not invent a location that is not suggested by the text.
                    Never return schema type names, property names, or placeholder tokens.
                    """
                )
                let response = try await session.respond(
                    to: "Parse this transaction description:\n\(trimmed)",
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

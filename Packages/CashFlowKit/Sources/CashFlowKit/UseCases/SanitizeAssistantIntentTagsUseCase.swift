import Foundation

/// Drops tags that merely echo the chosen category (common model hallucination).
public enum SanitizeAssistantIntentTagsUseCase: Sendable {
    public static func execute(
        appliesCategory: Bool,
        categoryID: CategoryID,
        tagNames: [String]
    ) -> [String] {
        let trimmed = tagNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard appliesCategory else { return trimmed }

        let categoryName = SystemCategory.category(for: categoryID).name
        return trimmed.filter {
            $0.localizedCaseInsensitiveCompare(categoryName) != .orderedSame
        }
    }
}

import Foundation
import Testing
@testable import CashFlowKit

@Suite("SanitizeAssistantIntentTagsUseCase")
struct SanitizeAssistantIntentTagsTests {
    @Test("Drops tags that duplicate the chosen category name")
    func dropsCategoryDuplicate() {
        let tags = SanitizeAssistantIntentTagsUseCase.execute(
            appliesCategory: true,
            categoryID: SystemCategory.income.id,
            tagNames: ["Income", "Bonus"]
        )
        #expect(tags == ["Bonus"])
    }

    @Test("Keeps unrelated tags when categorizing")
    func keepsDistinctTags() {
        let tags = SanitizeAssistantIntentTagsUseCase.execute(
            appliesCategory: true,
            categoryID: SystemCategory.dining.id,
            tagNames: ["Thailand"]
        )
        #expect(tags == ["Thailand"])
    }

    @Test("Leaves tags alone when not applying a category")
    func tagOnlyUnchanged() {
        let tags = SanitizeAssistantIntentTagsUseCase.execute(
            appliesCategory: false,
            categoryID: SystemCategory.other.id,
            tagNames: ["Income"]
        )
        #expect(tags == ["Income"])
    }
}

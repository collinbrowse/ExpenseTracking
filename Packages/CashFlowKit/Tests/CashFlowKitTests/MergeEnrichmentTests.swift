import Testing
import Foundation
@testable import CashFlowKit

@Suite("MergeSyncPolicy enrichment")
struct MergeEnrichmentTests {
    @Test("Preserves enrichment when description unchanged")
    func preservesEnrichment() {
        let local = Transaction(
            id: TransactionID("1"),
            accountID: AccountID("a"),
            externalID: "e1",
            amount: -10,
            postedDate: .now,
            description: "STARBUCKS  SEATTLE WA",
            categoryID: SystemCategory.dining.id,
            enrichedTitle: "Starbucks",
            enrichedLocation: "Seattle WA",
            titleSource: .llm
        )
        let remote = Transaction(
            id: TransactionID("1"),
            accountID: AccountID("a"),
            externalID: "e1",
            amount: -12,
            postedDate: .now,
            description: "STARBUCKS  SEATTLE WA",
            categoryID: SystemCategory.dining.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote)
        #expect(merged.enrichedTitle == "Starbucks")
        #expect(merged.enrichedLocation == "Seattle WA")
        #expect(merged.titleSource == .llm)
        #expect(merged.amount == -12)
    }

    @Test("Clears enrichment when description changes")
    func clearsEnrichmentOnDescriptionChange() {
        let local = Transaction(
            id: TransactionID("1"),
            accountID: AccountID("a"),
            externalID: "e1",
            amount: -10,
            postedDate: .now,
            description: "OLD MERCHANT",
            categoryID: SystemCategory.other.id,
            userEditedCategory: false,
            enrichedTitle: "Old",
            enrichedLocation: "Denver CO"
        )
        let remote = Transaction(
            id: TransactionID("1"),
            accountID: AccountID("a"),
            externalID: "e1",
            amount: -10,
            postedDate: .now,
            description: "NEW MERCHANT  AUSTIN TX",
            categoryID: SystemCategory.other.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote)
        #expect(merged.enrichedTitle == nil)
        #expect(merged.enrichedLocation == nil)
        #expect(merged.description == "NEW MERCHANT  AUSTIN TX")
    }

    @Test("displayTitle prefers enrichment")
    func displayTitlePrefersEnrichment() {
        let tx = Transaction(
            id: TransactionID("1"),
            accountID: AccountID("a"),
            externalID: "e1",
            amount: -5,
            postedDate: .now,
            description: "RAW BANK TEXT  CITY ST",
            categoryID: SystemCategory.other.id,
            enrichedTitle: "Clean Name",
            enrichedLocation: "Bangkok"
        )
        #expect(tx.displayTitle == "Clean Name")
        #expect(tx.displayLocation == "Bangkok")
    }
}

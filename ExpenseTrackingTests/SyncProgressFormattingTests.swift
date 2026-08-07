import Testing
@testable import ExpenseTracking
import CashFlowKit

@Suite("SyncProgressFormatting")
struct SyncProgressFormattingTests {
    @Test("Downloading and enriching include unit counts when known")
    func titlesIncludeUnits() {
        let downloading = SyncProgress(phase: .downloading, completedUnits: 2, totalUnits: 9)
        #expect(SyncProgressFormatting.title(for: downloading) == "Downloading… 2 of 9")

        let enriching = SyncProgress(phase: .enriching, completedUnits: 3, totalUnits: 12)
        #expect(SyncProgressFormatting.title(for: enriching) == "Improving transactions… 3 of 12")

        #expect(SyncProgressFormatting.title(for: SyncProgress(phase: .preparing)) == "Starting sync…")
        #expect(SyncProgressFormatting.title(for: SyncProgress(phase: .saving)) == "Saving updates…")
        let backfill = SyncProgress(phase: .backfillingHistory, completedUnits: 1, totalUnits: 4)
        #expect(SyncProgressFormatting.title(for: backfill) == "Importing history… 1 of 4")
    }
}

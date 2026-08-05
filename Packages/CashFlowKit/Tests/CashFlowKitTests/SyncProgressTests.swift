import Testing
import CashFlowKit

@Suite("SyncProgress")
struct SyncProgressTests {
    @Test("fractionCompleted is nil when total unknown or zero")
    func indeterminateFraction() {
        #expect(SyncProgress(phase: .preparing).fractionCompleted == nil)
        #expect(
            SyncProgress(phase: .downloading, completedUnits: 0, totalUnits: 0)
                .fractionCompleted == nil
        )
    }

    @Test("fractionCompleted clamps to 1")
    func clampsFraction() {
        let mid = SyncProgress(phase: .downloading, completedUnits: 2, totalUnits: 4)
        #expect(mid.fractionCompleted == 0.5)
        let over = SyncProgress(phase: .enriching, completedUnits: 5, totalUnits: 4)
        #expect(over.fractionCompleted == 1)
    }
}

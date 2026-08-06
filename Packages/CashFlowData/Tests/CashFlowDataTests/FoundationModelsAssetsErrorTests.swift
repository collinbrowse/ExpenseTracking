import Foundation
import Testing
@testable import CashFlowData
import CashFlowKit

@Suite("FoundationModelsWorkCoordinator assets")
struct FoundationModelsAssetsErrorTests {
    @Test("Detects Model Catalog NSError domains")
    func detectsCatalogError() {
        let underlying = NSError(
            domain: "com.apple.UnifiedAssetFramework",
            code: 5000,
            userInfo: [
                NSLocalizedFailureReasonErrorKey:
                    "There are no underlying assets (neither atomic instance nor asset roots) for consistency token for asset set com.apple.modelcatalog",
            ]
        )
        let outer = NSError(
            domain: "ModelManagerServices.ModelManagerError",
            code: 1026,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        #expect(FoundationModelsWorkCoordinator.isAssetsUnavailableError(outer))
    }

    @Test("Rate limit text is not treated as missing assets")
    func rateLimitIsNotAssetsFailure() {
        let rateLimited = NSError(
            domain: "ModelManagerServices.ModelManagerError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Client rate limit exceeded, try again later"]
        )
        #expect(!FoundationModelsWorkCoordinator.isAssetsUnavailableError(rateLimited))
        #expect(FoundationModelsWorkCoordinator.isRateLimitedError(rateLimited))
    }

    @Test("Sticky unavailable blocks exclusive work")
    func stickyBlocksWork() async throws {
        let coordinator = FoundationModelsWorkCoordinator()
        await coordinator.noteAssetsUnavailable()
        #expect(await coordinator.isAssetsUnavailable)
        do {
            _ = try await coordinator.runExclusive { "ok" }
            Issue.record("Expected intelligenceUnavailable")
        } catch let error as CashFlowError {
            #expect(error == .intelligenceUnavailable)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test("Rate limit pause is sticky until waited out")
    func rateLimitPauseSticky() async {
        let coordinator = FoundationModelsWorkCoordinator()
        await coordinator.setAppForeground(true)
        await coordinator.noteRateLimited()
        #expect(await coordinator.isRateLimitPaused)
        #expect(await coordinator.rateLimitPauseRemaining > 0)
    }

    @Test("Backgrounding the app switches to background pacing")
    func backgroundPacingFollowsScenePhase() async {
        let coordinator = FoundationModelsWorkCoordinator()
        await coordinator.setAppForeground(false)
        #expect(await coordinator.isPrefersBackgroundPacing)
        await coordinator.setAppForeground(true)
        let prefersBackground = await coordinator.isPrefersBackgroundPacing
        #expect(!prefersBackground)
    }

    @Test("Foregrounding mid-task does not relax a background drain's pacing")
    func backgroundClaimOutlivesForegrounding() async {
        let coordinator = FoundationModelsWorkCoordinator()
        await coordinator.setAppForeground(false)
        await coordinator.beginBackgroundWork()

        // User opens the app while the BGProcessingTask is still draining.
        await coordinator.setAppForeground(true)
        #expect(await coordinator.isPrefersBackgroundPacing)

        await coordinator.endBackgroundWork()
        let prefersBackground = await coordinator.isPrefersBackgroundPacing
        #expect(!prefersBackground)
    }
}

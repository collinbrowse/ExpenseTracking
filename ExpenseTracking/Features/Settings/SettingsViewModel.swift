import Foundation
import Observation
import SwiftUI
import CashFlowKit

@MainActor
@Observable
final class SettingsViewModel {
    let ruleRepository: any CategorizationRuleRepository
    let ruleApplying: any CategorizationRuleApplying
    let accountRepository: any AccountRepository
    let tagRepository: any TagRepository
    let ruleDrafting: any CategorizationRuleDrafting
    let availabilityChecker: any OnDeviceModelAvailabilityChecking
    let appLock: AppLockViewModel
    let syncServing: any SyncServing
    let backgroundEnrichment: any BackgroundEnrichmentScheduling
    let cleanupState: any TitleCleanupStateStoring

    var historyStatus: HistoryImportStatus?
    var selectedLookback: HistoryLookbackYears = .default
    var cleanupErrorMessage: String?
    var isCleaningUpTitles = false
    var cleanupPhase: EnrichmentProgress.Phase = .running
    var cleanupDetail: String?
    var cleanupCompleted = 0
    var cleanupTotal = 0
    var modelAvailability: OnDeviceModelAvailability = .unavailable
    var ruleCount = 0
    /// True after a drain stops early with titles still remaining — show Resume.
    /// Mirrored to `cleanupState` so a relaunch still offers Resume.
    private(set) var isTitleCleanupPaused: Bool
    /// True while `startTitleCleanup` owns the drain lifecycle (ignore hub `nil` races).
    private var ownsActiveDrain = false

    private var progressObservation: Task<Void, Never>?

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    init(
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        accountRepository: any AccountRepository,
        tagRepository: any TagRepository,
        ruleDrafting: any CategorizationRuleDrafting,
        availabilityChecker: any OnDeviceModelAvailabilityChecking,
        appLock: AppLockViewModel,
        syncServing: any SyncServing,
        backgroundEnrichment: any BackgroundEnrichmentScheduling,
        cleanupState: any TitleCleanupStateStoring
    ) {
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.accountRepository = accountRepository
        self.tagRepository = tagRepository
        self.ruleDrafting = ruleDrafting
        self.availabilityChecker = availabilityChecker
        self.appLock = appLock
        self.syncServing = syncServing
        self.backgroundEnrichment = backgroundEnrichment
        self.cleanupState = cleanupState
        self.isTitleCleanupPaused = cleanupState.isPaused()
    }

    private func setTitleCleanupPaused(_ paused: Bool) {
        isTitleCleanupPaused = paused
        cleanupState.setPaused(paused)
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var requireLockBinding: Binding<Bool> {
        Binding(
            get: { self.appLock.isEnabled },
            set: { newValue in
                Task { await self.appLock.setEnabled(newValue) }
            }
        )
    }

    var isHistoryComplete: Bool {
        historyStatus?.historyComplete == true
    }

    var historyCoverageText: String {
        guard let status = historyStatus else { return "Not linked yet" }
        if status.historyComplete {
            if let earliest = status.earliestFetchedDisplay(formatter: monthFormatter) {
                return "History imported back to \(earliest)"
            }
            return "History import complete"
        }
        if let earliest = status.earliestFetchedDisplay(formatter: monthFormatter) {
            return "Imported back to \(earliest)"
        }
        return "Waiting to import history"
    }

    var showHistoryProgress: Bool {
        guard let status = historyStatus else { return false }
        return !status.historyComplete
    }

    var isCoolingDown: Bool {
        isCleaningUpTitles && cleanupPhase == .coolingDown
    }

    var isTitleCleanupComplete: Bool {
        !isCleaningUpTitles && historyStatus?.needsTitleCleanup != true
    }

    var showTitleCleanupProgress: Bool {
        isCleaningUpTitles
    }

    var titleCleanupText: String {
        if isCleaningUpTitles {
            if isCoolingDown {
                if cleanupTotal > 0 {
                    return "Waiting for Apple Intelligence… \(cleanupCompleted) of \(cleanupTotal)"
                }
                return "Waiting for Apple Intelligence…"
            }
            if cleanupTotal > 0 {
                return "Cleaning titles… \(cleanupCompleted) of \(cleanupTotal)"
            }
            return "Cleaning titles…"
        }
        guard let status = historyStatus else { return "—" }
        if status.untitledCount == 0 {
            return finishedTitlesCopy
        }
        if isTitleCleanupPaused {
            return "Paused · \(status.untitledCount) titles left"
        }
        let lookups = status.distinctMerchantLookupsRemaining
        return "\(status.untitledCount) titles left · \(lookups) merchant lookups"
    }

    var finishedTitlesCopy: String {
        switch ruleCount {
        case 0:
            return "All titles processed"
        case 1:
            return "All titles processed with your 1 rule applied"
        default:
            return "All titles processed with your \(ruleCount) rules applied"
        }
    }

    var titleCleanupFraction: Double {
        guard cleanupTotal > 0 else { return 0 }
        return min(1, Double(cleanupCompleted) / Double(cleanupTotal))
    }

    var titleCleanupFootnote: String? {
        if isCleaningUpTitles {
            if isCoolingDown {
                return cleanupDetail
                    ?? "Apple Intelligence hit a temporary limit. Waiting to continue…"
            }
            return "Keep the app open — background processing is slower and more likely to pause."
        }
        if isTitleCleanupComplete {
            return nil
        }
        switch modelAvailability {
        case .available:
            return "Uses on-device Apple Intelligence. Keep the app open to process titles quickest. The rest can be completed in the background"
        case .appleIntelligenceOff:
            return "Turn on Apple Intelligence in Settings to clean up titles automatically. You can still rename with rules."
        case .modelNotReady:
            return "Apple Intelligence is downloading or unavailable right now. Try again when it’s ready, or rename with rules."
        case .deviceNotEligible, .unavailable:
            return "This device can’t run on-device title cleanup. Use rename rules to clean titles."
        }
    }

    var canCleanUpTitles: Bool {
        historyStatus?.needsTitleCleanup == true
            && !isCleaningUpTitles
            && modelAvailability == .available
    }

    var titleCleanupActionTitle: String {
        isTitleCleanupPaused ? "Resume" : "Clean up transaction titles"
    }

    /// Shows a badge on the Settings tab while cleanup runs.
    var settingsTabBadge: String? {
        isCleaningUpTitles ? "…" : nil
    }

    func startObservingEnrichmentProgress() {
        progressObservation?.cancel()
        progressObservation = Task { [weak self] in
            guard let self else { return }
            for await progress in self.backgroundEnrichment.enrichmentProgressUpdates() {
                guard !Task.isCancelled else { return }
                await self.applyEnrichmentProgress(progress)
            }
        }
    }

    func stopObservingEnrichmentProgress() {
        progressObservation?.cancel()
        progressObservation = nil
    }

    /// - Parameter refreshTitleBacklog: When `false`, bank-history fields refresh but the
    ///   idle "N titles left" line keeps its previous snapshot. Use after scene-active
    ///   reloads so opportunistic work can't change the number under the user's nose.
    func reloadHistoryStatus(refreshTitleBacklog: Bool = true) async {
        let previous = historyStatus
        async let status = syncServing.historyImportStatus()
        async let availability = availabilityChecker.availability()
        async let rules = loadRuleCount()
        var next = await status
        if !refreshTitleBacklog, !isCleaningUpTitles, let previous {
            next = next?.preservingTitleBacklog(from: previous)
        }
        historyStatus = next
        modelAvailability = await availability
        ruleCount = await rules
        if let lookback = historyStatus?.lookback {
            selectedLookback = lookback
        }
        if historyStatus?.needsTitleCleanup != true {
            setTitleCleanupPaused(false)
        }
    }

    func applyLookback(_ lookback: HistoryLookbackYears) async {
        selectedLookback = lookback
        do {
            try await syncServing.setHistoryLookback(lookback)
            await reloadHistoryStatus()
        } catch {
            cleanupErrorMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't update history lookback."
            )
        }
    }

    /// Shared entry point for Settings button and the first-sync prompt.
    func startTitleCleanup(expectedUntitled: Int? = nil) async {
        guard !isCleaningUpTitles else { return }

        cleanupErrorMessage = nil
        setTitleCleanupPaused(false)
        // Re-read the backlog before a user-started run — the idle line may be a
        // preserved snapshot that shouldn't drive expected totals.
        if expectedUntitled == nil {
            await reloadHistoryStatus(refreshTitleBacklog: true)
        }
        let expected = expectedUntitled ?? historyStatus?.untitledCount ?? 0
        guard expected > 0 else {
            setTitleCleanupPaused(false)
            return
        }
        ownsActiveDrain = true
        // Immediate UI so the prompt / button feel responsive.
        isCleaningUpTitles = true
        cleanupPhase = .running
        cleanupDetail = nil
        cleanupCompleted = 0
        cleanupTotal = max(expected, 1)

        let availability = await availabilityChecker.availability()
        modelAvailability = availability
        guard availability == .available else {
            isCleaningUpTitles = false
            ownsActiveDrain = false
            cleanupErrorMessage = titleCleanupFootnote
            await reloadHistoryStatus(refreshTitleBacklog: true)
            return
        }

        let outcome = await backgroundEnrichment.runFullEnrichmentDrain(expectedTotal: expected) {
            [weak self] completed, total in
            Task { @MainActor in
                self?.cleanupCompleted = completed
                self?.cleanupTotal = max(total, completed, 1)
            }
        }

        ownsActiveDrain = false
        isCleaningUpTitles = false
        cleanupPhase = .running
        cleanupDetail = nil
        await reloadHistoryStatus()
        applyDrainOutcome(outcome)
    }

    /// Back-compat name used by the Settings button.
    func cleanUpTitles() async {
        await startTitleCleanup()
    }

    private func loadRuleCount() async -> Int {
        (try? await ruleRepository.fetchAll())?.count ?? 0
    }

    private func applyDrainOutcome(_ outcome: EnrichmentDrainOutcome) {
        switch outcome {
        case .completed:
            setTitleCleanupPaused(false)
            cleanupErrorMessage = nil
        case .interruptedByRateLimit, .interrupted:
            setTitleCleanupPaused(historyStatus?.needsTitleCleanup == true)
            cleanupErrorMessage = nil
        }
    }

    private func applyEnrichmentProgress(_ progress: EnrichmentProgress?) async {
        if let progress, progress.isRunning {
            isCleaningUpTitles = true
            cleanupPhase = progress.phase
            cleanupDetail = progress.detail
            cleanupCompleted = progress.completed
            cleanupTotal = max(progress.total, progress.completed, cleanupTotal, 1)
        } else if isCleaningUpTitles, !ownsActiveDrain {
            isCleaningUpTitles = false
            cleanupPhase = .running
            cleanupDetail = nil
            await reloadHistoryStatus()
        }
    }
}

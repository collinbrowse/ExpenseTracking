import Foundation
import CashFlowKit

/// Routes link/sync to Demo or SimpleFIN based on how the user connected.
public actor CompositeBankLinkingService: BankLinkingServing {
    public enum Mode: Sendable {
        case none
        case demo
        case simpleFIN
    }

    private let demo: DemoBankLinkingService
    private let simpleFIN: SimpleFINBankLinkingService
    private var mode: Mode

    public init(
        demo: DemoBankLinkingService,
        simpleFIN: SimpleFINBankLinkingService,
        initialMode: Mode = .none
    ) {
        self.demo = demo
        self.simpleFIN = simpleFIN
        self.mode = initialMode
    }

    /// Protocol requirement; prefer `activeProviderName()` / `connectionStatus().providerName` for persistence.
    public nonisolated var providerName: String { "Accounts" }

    public func activeProviderName() async -> String {
        await resolveModeIfNeeded()
        switch mode {
        case .none: return "None"
        case .demo: return demo.providerName
        case .simpleFIN: return simpleFIN.providerName
        }
    }

    public func connectionStatus() async -> LinkedConnection {
        await resolveModeIfNeeded()
        switch mode {
        case .none:
            return LinkedConnection(isLinked: false, providerName: "None")
        case .demo:
            return await demo.connectionStatus()
        case .simpleFIN:
            return await simpleFIN.connectionStatus()
        }
    }

    public func link(withSetupToken token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "demo" || lower == "demo-large" {
            // Mutual exclusion: clear SimpleFIN credentials before enabling Demo.
            try await simpleFIN.unlink(removeLocalData: false)
            try await demo.link(withSetupToken: trimmed)
            mode = .demo
            return
        }
        // Mutual exclusion: clear Demo session before enabling SimpleFIN.
        try await demo.unlink(removeLocalData: false)
        try await simpleFIN.link(withSetupToken: trimmed)
        mode = .simpleFIN
    }

    public func unlink(removeLocalData: Bool) async throws {
        await resolveModeIfNeeded()
        switch mode {
        case .demo:
            try await demo.unlink(removeLocalData: removeLocalData)
        case .simpleFIN:
            try await simpleFIN.unlink(removeLocalData: removeLocalData)
        case .none:
            try await simpleFIN.unlink(removeLocalData: removeLocalData)
            try await demo.unlink(removeLocalData: removeLocalData)
        }
        mode = .none
    }

    public func fetchAccounts(
        startDate: Date?,
        endDate: Date?
    ) async throws -> RemoteSyncPayload {
        try await fetchAccounts(startDate: startDate, endDate: endDate, onWindowProgress: nil)
    }

    public func fetchAccounts(
        startDate: Date?,
        endDate: Date?,
        onWindowProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async throws -> RemoteSyncPayload {
        await resolveModeIfNeeded()
        switch mode {
        case .none:
            throw CashFlowError.notLinked
        case .demo:
            return try await demo.fetchAccounts(
                startDate: startDate,
                endDate: endDate,
                onWindowProgress: onWindowProgress
            )
        case .simpleFIN:
            return try await simpleFIN.fetchAccounts(
                startDate: startDate,
                endDate: endDate,
                onWindowProgress: onWindowProgress
            )
        }
    }

    public func setMode(_ mode: Mode) {
        self.mode = mode
    }

    /// Restores an in-memory Demo session from durable `ConnectionEntity` after process launch.
    public func adoptDurableDemoLink() async {
        await demo.adoptLinkedState(true)
        mode = .demo
    }

    /// After process launch, `mode` is `.none` even if SimpleFIN credentials remain in Keychain.
    private func resolveModeIfNeeded() async {
        guard mode == .none else { return }
        let simpleStatus = await simpleFIN.connectionStatus()
        if simpleStatus.isLinked {
            mode = .simpleFIN
            return
        }
        let demoStatus = await demo.connectionStatus()
        if demoStatus.isLinked {
            mode = .demo
        }
    }
}

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

    /// Stable label; active provider is reflected in `connectionStatus()`.
    public nonisolated let providerName = "Accounts"

    public func connectionStatus() async -> LinkedConnection {
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
            try await demo.link(withSetupToken: trimmed)
            mode = .demo
            return
        }
        try await simpleFIN.link(withSetupToken: trimmed)
        mode = .simpleFIN
    }

    public func unlink(removeLocalData: Bool) async throws {
        switch mode {
        case .demo:
            try await demo.unlink(removeLocalData: removeLocalData)
        case .simpleFIN:
            try await simpleFIN.unlink(removeLocalData: removeLocalData)
        case .none:
            break
        }
        mode = .none
    }

    public func fetchAccounts(
        startDate: Date?,
        endDate: Date?
    ) async throws -> RemoteSyncPayload {
        switch mode {
        case .none:
            throw CashFlowError.notLinked
        case .demo:
            return try await demo.fetchAccounts(startDate: startDate, endDate: endDate)
        case .simpleFIN:
            return try await simpleFIN.fetchAccounts(startDate: startDate, endDate: endDate)
        }
    }

    public func setMode(_ mode: Mode) {
        self.mode = mode
    }
}

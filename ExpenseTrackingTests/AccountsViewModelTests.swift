import Foundation
import Testing
import CashFlowKit
@testable import ExpenseTracking

@Suite("AccountsViewModel")
@MainActor
struct AccountsViewModelTests {
    @Test("Connection status and reconnect reflect per-account sync issues")
    func syncIssuesSurfaceNeedsAttention() async {
        let account = Account(
            id: AccountID("a1"),
            externalID: "ext-1",
            name: "Checking",
            institutionName: "Chase",
            currencyCode: "USD",
            balance: 10,
            balanceDate: .now,
            syncIssue: "Authentication failed for Chase"
        )
        let sync = MockAccountsSyncServing(
            connection: LinkedConnection(
                isLinked: true,
                providerName: "SimpleFIN",
                needsReauth: false,
                lastSuccessfulSyncAt: .now
            )
        )
        let accounts = MockAccountRepository(accounts: [account])
        let vm = AccountsViewModel(
            connectionLifecycle: MockConnectionLifecycle(),
            syncServing: sync,
            accountRepository: accounts,
            useLargeDemoSeed: false
        )

        await vm.refreshStatus()

        #expect(vm.hasAccountSyncIssues)
        #expect(vm.connectionStatusLabel == "Needs attention")
        #expect(vm.showsReconnectAction)
        #expect(vm.syncDisplay(for: account) == .issue("Authentication failed for Chase"))
    }

    @Test("Healthy linked accounts stay Linked without reconnect")
    func healthyStaysLinked() async {
        let account = Account(
            id: AccountID("a1"),
            externalID: "ext-1",
            name: "Checking",
            institutionName: "Chase",
            currencyCode: "USD",
            balance: 10,
            balanceDate: .now
        )
        let sync = MockAccountsSyncServing(
            connection: LinkedConnection(
                isLinked: true,
                providerName: "SimpleFIN",
                needsReauth: false,
                lastSuccessfulSyncAt: .now
            )
        )
        let vm = AccountsViewModel(
            connectionLifecycle: MockConnectionLifecycle(),
            syncServing: sync,
            accountRepository: MockAccountRepository(accounts: [account]),
            useLargeDemoSeed: false
        )

        await vm.refreshStatus()

        #expect(!vm.hasAccountSyncIssues)
        #expect(vm.connectionStatusLabel == "Linked")
        #expect(!vm.showsReconnectAction)
        #expect(vm.syncDisplay(for: account) == .healthy)
    }
}

private struct MockAccountsSyncServing: SyncServing {
    let connection: LinkedConnection

    func syncNow() async throws -> LinkedConnection { connection }
    func connectionStatus() async -> LinkedConnection { connection }
}

private struct MockConnectionLifecycle: ConnectionLifecycleServing {
    func replaceAndLink(withSetupToken token: String) async throws -> LinkedConnection {
        LinkedConnection(isLinked: true, providerName: "SimpleFIN")
    }

    func disconnect(deleteLocalData: Bool) async throws -> LinkedConnection {
        LinkedConnection(isLinked: false, providerName: "None")
    }

    func resetLocalDataKeepingLink() async throws -> LinkedConnection {
        LinkedConnection(isLinked: true, providerName: "SimpleFIN")
    }

    func eraseEverything() async throws {}
}

private struct MockAccountRepository: AccountRepository {
    let accounts: [Account]

    func fetchAll() async throws -> [Account] { accounts }
    func updateName(accountID: AccountID, name: String) async throws {}
}

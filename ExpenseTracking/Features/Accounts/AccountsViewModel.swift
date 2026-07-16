import Foundation
import Observation
import UIKit
import CashFlowKit
import CashFlowData

@MainActor
@Observable
final class AccountsViewModel {
    private let bankLinking: CompositeBankLinkingService
    private let syncServing: SyncCoordinator
    private let accountRepository: any AccountRepository
    private let resetter: LocalDataResetter
    private let useLargeDemoSeed: Bool

    var accounts: [Account] = []
    var connection: LinkedConnection = .init(isLinked: false, providerName: "None")
    var setupToken = ""
    var showLinkSheet = false
    var isWorking = false
    var message: String?
    var showOnboarding: Bool
    /// Bumped after any successful sync/demo load so Home/Transactions reload.
    var storeEpoch: Int = 0

    init(
        bankLinking: CompositeBankLinkingService,
        syncServing: SyncCoordinator,
        accountRepository: any AccountRepository,
        resetter: LocalDataResetter,
        useLargeDemoSeed: Bool
    ) {
        self.bankLinking = bankLinking
        self.syncServing = syncServing
        self.accountRepository = accountRepository
        self.resetter = resetter
        self.useLargeDemoSeed = useLargeDemoSeed
        self.showOnboarding = !UserDefaults.standard.bool(forKey: "didCompleteOnboarding")
    }

    func onAppear() async {
        await refreshStatus()
    }

    func refreshStatus() async {
        connection = await syncServing.connectionStatus()
        accounts = (try? await accountRepository.fetchAll()) ?? []
    }

    func loadDemo() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let token = useLargeDemoSeed ? "demo-large" : "demo"
            try await bankLinking.link(withSetupToken: token)
            _ = try await syncServing.syncNow()
            completeOnboarding()
            message = "Demo data loaded."
            await refreshStatus()
            storeEpoch += 1
        } catch {
            message = "Couldn't load demo data."
        }
    }

    func linkSimpleFIN() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await bankLinking.link(withSetupToken: setupToken)
            _ = try await syncServing.syncNow()
            setupToken = ""
            showLinkSheet = false
            completeOnboarding()
            message = "Account linked."
            await refreshStatus()
            storeEpoch += 1
        } catch CashFlowError.unauthorized {
            message = "Token may be compromised or already used. Create a new SimpleFIN token."
        } catch {
            message = "Couldn't link SimpleFIN."
        }
    }

    func syncNow() async {
        isWorking = true
        defer { isWorking = false }
        do {
            connection = try await syncServing.syncNow()
            message = "Synced."
            await refreshStatus()
            storeEpoch += 1
        } catch CashFlowError.unauthorized {
            message = "Reconnect required."
            await refreshStatus()
        } catch {
            message = "Couldn't sync."
        }
    }

    func disconnect(removeLocalData: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await bankLinking.unlink(removeLocalData: removeLocalData)
            if removeLocalData {
                try await resetter.resetAll()
            }
            message = "Disconnected."
            await refreshStatus()
            storeEpoch += 1
        } catch {
            message = "Couldn't disconnect."
        }
    }

    func resetLocalData() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await resetter.resetAll()
            message = "Local data reset."
            await refreshStatus()
            storeEpoch += 1
        } catch {
            message = "Couldn't reset local data."
        }
    }

    func openSimpleFINCreate() {
        if let url = URL(string: "https://bridge.simplefin.org/simplefin/create") {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }

    private func completeOnboarding() {
        showOnboarding = false
        UserDefaults.standard.set(true, forKey: "didCompleteOnboarding")
    }

    func dismissOnboarding() {
        completeOnboarding()
    }
}

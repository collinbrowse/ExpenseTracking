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
    let appLock: AppLockViewModel

    init(
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        accountRepository: any AccountRepository,
        appLock: AppLockViewModel
    ) {
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.accountRepository = accountRepository
        self.appLock = appLock
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
}

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

    init(
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        accountRepository: any AccountRepository,
        tagRepository: any TagRepository,
        ruleDrafting: any CategorizationRuleDrafting,
        availabilityChecker: any OnDeviceModelAvailabilityChecking,
        appLock: AppLockViewModel
    ) {
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.accountRepository = accountRepository
        self.tagRepository = tagRepository
        self.ruleDrafting = ruleDrafting
        self.availabilityChecker = availabilityChecker
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

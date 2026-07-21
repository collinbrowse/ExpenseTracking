import Foundation
import SwiftData
import Testing
@testable import CashFlowData

@Suite("ModelContainerFactory")
struct ModelContainerFactoryTests {
    @Test("In-memory container loads with new AccountEntity defaults")
    func inMemoryLoads() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(
            AccountEntity(
                id: "1",
                externalID: "ext",
                name: "Checking",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: 1,
                balanceDate: .now
            )
        )
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<AccountEntity>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.userEditedName == false)
    }

    @Test("Store directories include App Group Application Support")
    func storeDirectoriesIncludeAppGroupApplicationSupport() {
        let groupID = "group.com.expensetracking.shared"
        let dirs = ModelContainerFactory.storeDirectories(appGroupID: groupID)
        #expect(!dirs.isEmpty)
        #expect(dirs.contains(where: { $0.path.contains("Application Support") }))
    }

    @Test("makeResilient succeeds when App Group is unavailable")
    func makeResilientWithoutAppGroup() {
        // Empty / nonsense group IDs resolve to no container URL — must not trap.
        let container = ModelContainerFactory.makeResilient(
            appGroupID: "group.com.expensetracking.unavailable-ci"
        )
        #expect(container.schema.entities.isEmpty == false)
    }
}

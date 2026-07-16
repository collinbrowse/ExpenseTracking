import Foundation
import SwiftData
import CashFlowKit

public actor LocalDataResetter {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    public func resetAll() async throws {
        let context = ModelContext(modelContainer)
        try context.delete(model: TransactionEntity.self)
        try context.delete(model: AccountEntity.self)
        try context.delete(model: ConnectionEntity.self)
        try context.save()
    }
}

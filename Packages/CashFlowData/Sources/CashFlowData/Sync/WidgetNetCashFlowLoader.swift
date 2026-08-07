import Foundation
import SwiftData
import CashFlowKit

public struct WidgetNetCashFlowTotals: Equatable, Sendable {
    public let net: Decimal
    public let incomeTotal: Decimal
    public let expenseTotal: Decimal
    public let rangeLabel: String

    public init(
        net: Decimal,
        incomeTotal: Decimal,
        expenseTotal: Decimal,
        rangeLabel: String
    ) {
        self.net = net
        self.incomeTotal = incomeTotal
        self.expenseTotal = expenseTotal
        self.rangeLabel = rangeLabel
    }
}

/// Computes widget net / in / out from the shared App Group SwiftData store (or an injected container for tests).
public struct WidgetNetCashFlowLoader: Sendable {
    private let injectedContainer: ModelContainer?
    private let appGroupID: String
    private let calculateNetCashFlow: CalculateNetCashFlowUseCase

    public init(appGroupID: String = NetSnapshotStore.defaultAppGroupID) {
        self.injectedContainer = nil
        self.appGroupID = appGroupID
        self.calculateNetCashFlow = CalculateNetCashFlowUseCase()
    }

    public init(
        modelContainer: ModelContainer,
        calculateNetCashFlow: CalculateNetCashFlowUseCase = CalculateNetCashFlowUseCase()
    ) {
        self.injectedContainer = modelContainer
        self.appGroupID = NetSnapshotStore.defaultAppGroupID
        self.calculateNetCashFlow = calculateNetCashFlow
    }

    public func load(
        timeFrame: WidgetCashFlowTimeFrame,
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> WidgetNetCashFlowTotals? {
        let range = timeFrame.dateRange(now: now, calendar: calendar)
        let label = timeFrame.rangeLabel()
        return await load(range: range, rangeLabel: label, now: now)
    }

    public func load(
        range: CashFlowDateRange,
        rangeLabel: String,
        now: Date = .now
    ) async -> WidgetNetCashFlowTotals? {
        guard let container = resolvedContainer() else { return nil }

        let repository = SwiftDataTransactionRepository(modelContainer: container)
        do {
            let transactions = try await repository.fetchPosted(in: range, now: now)
            let result = calculateNetCashFlow.execute(
                transactions: transactions,
                range: range,
                now: now
            )
            return WidgetNetCashFlowTotals(
                net: result.net,
                incomeTotal: result.incomeTotal,
                expenseTotal: result.expenseTotal,
                rangeLabel: rangeLabel
            )
        } catch {
            return nil
        }
    }

    private func resolvedContainer() -> ModelContainer? {
        if let injectedContainer {
            return injectedContainer
        }
        return ModelContainerFactory.makeSharedStoreIfAvailable(appGroupID: appGroupID)
    }
}

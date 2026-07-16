import Foundation
import Observation
import CashFlowKit
import CashFlowData

enum HomeDisplayState: Equatable {
    case empty
    case loading
    case populated
}

@MainActor
@Observable
final class HomeViewModel {
    private let transactionRepository: any TransactionRepository
    private let syncServing: any SyncServing
    private let calculateNetCashFlow: CalculateNetCashFlowUseCase
    private let connectivity: ConnectivityMonitor

    var selectedOption: HomeRangeOption = .month
    var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    var customEnd: Date = .now
    var result: NetCashFlowResult = .init(
        net: 0,
        incomeTotal: 0,
        expenseTotal: 0,
        dailyPoints: []
    )
    var isRefreshing = false
    /// Starts true so the first paint is a loader, not a flash of the empty state.
    var isLoading = true
    var bannerMessage: String?
    var isOffline = false
    var showCustomRange = false
    var hasData = false
    /// Bumped when chart-worthy data lands so the chart can replay its entrance animation.
    var chartAnimationToken = 0

    init(
        transactionRepository: any TransactionRepository,
        syncServing: any SyncServing,
        calculateNetCashFlow: CalculateNetCashFlowUseCase,
        connectivity: ConnectivityMonitor
    ) {
        self.transactionRepository = transactionRepository
        self.syncServing = syncServing
        self.calculateNetCashFlow = calculateNetCashFlow
        self.connectivity = connectivity
    }

    var selectedRange: CashFlowDateRange {
        selectedOption.dateRange(customStart: customStart, customEnd: customEnd)
    }

    var displayState: HomeDisplayState {
        if isLoading { return .loading }
        if hasData { return .populated }
        return .empty
    }

    func onAppear() async {
        isOffline = !connectivity.isOnline
        await reload(preferLoadingIndicator: !hasData)
    }

    func selectOption(_ option: HomeRangeOption) async {
        if option == .custom {
            showCustomRange = true
            return
        }
        selectedOption = option
        await reload(preferLoadingIndicator: false)
    }

    func applyCustomRange() async {
        selectedOption = .custom
        showCustomRange = false
        await reload(preferLoadingIndicator: false)
    }

    /// - Parameter preferLoadingIndicator: When true (e.g. empty → first data), show the centered loader.
    func reload(preferLoadingIndicator: Bool = true) async {
        let wasEmpty = !hasData
        let shouldShowLoader = preferLoadingIndicator && wasEmpty
        if shouldShowLoader {
            isLoading = true
        }
        defer { isLoading = false }

        do {
            let transactions = try await transactionRepository.fetchPosted(
                in: selectedRange,
                now: .now
            )
            let nextHasData = !transactions.isEmpty
            let nextResult = calculateNetCashFlow.execute(
                transactions: transactions,
                range: selectedRange
            )

            hasData = nextHasData
            result = nextResult

            if nextHasData && (wasEmpty || shouldShowLoader) {
                chartAnimationToken += 1
            }
        } catch {
            bannerMessage = "Couldn't load transactions."
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        isOffline = !connectivity.isOnline
        let wasEmpty = !hasData
        if wasEmpty {
            isLoading = true
        }
        do {
            let status = try await syncServing.syncNow()
            if !status.providerMessages.isEmpty {
                bannerMessage = status.providerMessages.joined(separator: " ")
            } else {
                bannerMessage = nil
            }
            await reload(preferLoadingIndicator: wasEmpty)
        } catch CashFlowError.cancelled {
            isLoading = false
            return
        } catch CashFlowError.unauthorized {
            bannerMessage = "Reconnect your account — access was revoked."
            await reload(preferLoadingIndicator: wasEmpty)
        } catch {
            let asOf = (await syncServing.connectionStatus()).lastSuccessfulSyncAt
            if let asOf {
                bannerMessage =
                    "Couldn't refresh — showing data as of \(DateFormatting.medium(asOf))."
            } else {
                bannerMessage = "Couldn't refresh. Showing last saved data."
            }
            await reload(preferLoadingIndicator: wasEmpty)
        }
    }

    var rangeTitle: String {
        switch selectedOption {
        case .month: "This Month"
        case .last30Days: "Last 30 Days"
        case .lastYear: "Last Year"
        case .custom: "Custom"
        }
    }
}

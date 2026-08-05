import SwiftUI
import CashFlowKit

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                if let progress = viewModel.syncProgress {
                    SyncProgressBanner(progress: progress)
                }

                if let banner = viewModel.bannerMessage {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("home.banner")
                }

                if viewModel.isOffline {
                    Text("Offline")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("home.offline")
                }

                Picker("Range", selection: Binding(
                    get: { viewModel.selectedOption },
                    set: { viewModel.selectOption($0) }
                )) {
                    ForEach(viewModel.availableRangeOptions) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("home.rangePicker")
                .disabled(viewModel.displayState == .loading)

                // Instant swaps only — animated switches stacked empty/loading/populated
                // and crushed the empty state. The chart owns the entrance motion.
                switch viewModel.displayState {
                case .loading:
                    loadingState
                case .empty:
                    emptyState
                case .populated:
                    populatedContent
                }
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle("Cash Flow")
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.onAppear()
        }
        .sheet(isPresented: $viewModel.showCustomRange) {
            NavigationStack {
                Form {
                    DatePicker("Start", selection: $viewModel.customStart, displayedComponents: .date)
                    DatePicker("End", selection: $viewModel.customEnd, displayedComponents: .date)
                }
                .navigationTitle("Custom Range")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { viewModel.showCustomRange = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            viewModel.applyCustomRange()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading activity…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .accessibilityIdentifier("home.loading")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading activity")
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No activity yet",
            systemImage: "chart.line.uptrend.xyaxis",
            description: Text("Link an account or load Demo data from Accounts.")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .accessibilityIdentifier("home.empty")
    }

    private var emptyRangeHint: some View {
        Text("No posted activity in this range.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("home.emptyRange")
    }

    private var populatedContent: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.rangeTitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Text(CurrencyFormatting.signedUSD(viewModel.result.net))
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.amountColor(for: viewModel.result.net))
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .accessibilityIdentifier("home.net")
                    .accessibilityLabel(
                        "Net cash flow \(CurrencyFormatting.signedUSD(viewModel.result.net))"
                    )

                HStack(spacing: 16) {
                    labeledAmount("In", viewModel.result.incomeTotal, positive: true)
                    labeledAmount("Out", viewModel.result.expenseTotal, positive: false)
                }

                if !viewModel.hasData {
                    emptyRangeHint
                }
            }

            if !viewModel.result.dailyPoints.isEmpty {
                NetCashFlowChartView(
                    points: viewModel.result.dailyPoints,
                    accentPositive: viewModel.result.net >= 0,
                    rangeTitle: viewModel.rangeTitle,
                    endNet: viewModel.result.net,
                    animationToken: viewModel.chartAnimationToken
                )
            }
        }
    }

    private func labeledAmount(_ title: String, _ amount: Decimal, positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text(CurrencyFormatting.usd(amount))
                .font(.headline)
                .foregroundStyle(positive ? Theme.positive : Theme.negative)
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
    }
}

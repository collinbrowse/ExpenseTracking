import WidgetKit
import SwiftUI
import AppIntents
import CashFlowData

struct CashFlowWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: NetCashFlowSnapshot?
}

struct CashFlowTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CashFlowWidgetEntry {
        CashFlowWidgetEntry(
            date: .now,
            snapshot: NetCashFlowSnapshot(
                net: 420,
                incomeTotal: 3200,
                expenseTotal: 2780,
                rangeLabel: "This Month"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CashFlowWidgetEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<CashFlowWidgetEntry>) -> Void
    ) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> CashFlowWidgetEntry {
        let snapshot = try? NetSnapshotStore().load()
        return CashFlowWidgetEntry(date: .now, snapshot: snapshot)
    }
}

struct CashFlowWidgetView: View {
    var entry: CashFlowWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot?.rangeLabel ?? "Cash Flow")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(netText)
                .font(.title.bold())
                .minimumScaleFactor(0.7)
            if let snapshot = entry.snapshot {
                Text("In \(usd(snapshot.incomeTotal)) · Out \(usd(snapshot.expenseTotal))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open the app to sync")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var netText: String {
        guard let net = entry.snapshot?.net else { return "—" }
        return usd(net, signed: true)
    }

    private func usd(_ value: Decimal, signed: Bool = false) -> String {
        let absFormatted = abs(value).formatted(.currency(code: "USD"))
        if !signed {
            return value.formatted(.currency(code: "USD"))
        }
        if value > 0 { return "+\(absFormatted)" }
        if value < 0 { return "−\(absFormatted)" }
        return absFormatted
    }
}

struct CashFlowWidget: Widget {
    let kind = "CashFlowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CashFlowTimelineProvider()) { entry in
            CashFlowWidgetView(entry: entry)
        }
        .configurationDisplayName("Net Cash Flow")
        .description("See this month's net cash flow at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct OpenCashFlowIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Cash Flow"
    static let description = IntentDescription("Opens the Cash Flow app.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@main
struct CashFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        CashFlowWidget()
    }
}

import SwiftUI
import CashFlowKit

enum SyncProgressFormatting {
    static func title(for progress: SyncProgress) -> String {
        switch progress.phase {
        case .preparing:
            return "Starting sync…"
        case .downloading:
            if let total = progress.totalUnits, total > 0 {
                return "Downloading… \(progress.completedUnits) of \(total)"
            }
            return "Downloading…"
        case .saving:
            return "Saving updates…"
        case .enriching:
            if let total = progress.totalUnits, total > 0 {
                return "Improving transactions… \(progress.completedUnits) of \(total)"
            }
            return "Improving transactions…"
        case .backfillingHistory:
            if let total = progress.totalUnits, total > 0 {
                return "Importing history… \(progress.completedUnits) of \(total)"
            }
            return "Importing history…"
        }
    }
}

struct SyncProgressBanner: View {
    let progress: SyncProgress

    var body: some View {
        let title = SyncProgressFormatting.title(for: progress)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier("sync.progress")
    }
}

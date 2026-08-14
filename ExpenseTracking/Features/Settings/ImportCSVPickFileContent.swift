import SwiftUI
import CashFlowKit

struct ImportCSVPickFileContent: View {
    var onChooseFile: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Choose a CSV file", systemImage: "doc.badge.plus")
        } description: {
            Text("Map columns, pick an account, resolve duplicates, then import. Rows run through the same categorization pipeline as bank sync.")
        } actions: {
            Button("Choose File…") { onChooseFile() }
                .accessibilityIdentifier("settings.import.chooseFile")
        }
    }
}

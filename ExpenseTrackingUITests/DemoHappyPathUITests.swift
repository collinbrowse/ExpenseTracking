import XCTest

/// Demo happy-path smoke: onboarding → Home net/chart → Insights → Transactions.
final class DemoHappyPathUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()

        let demoButton = app.buttons["onboarding.demo"]
        if demoButton.waitForExistence(timeout: 8) {
            demoButton.tap()
        }

        // Home — net and dual-color chart
        let net = app.descendants(matching: .any)["home.net"]
        XCTAssertTrue(net.waitForExistence(timeout: 20), "Home net should appear after Demo load")

        let chart = app.descendants(matching: .any)["home.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10), "Home chart should be present")

        // Insights tab
        app.tabBars.buttons["Insights"].tap()
        let insightsRoot = app.descendants(matching: .any)["insights.root"]
        let insightsRange = app.descendants(matching: .any)["insights.rangePicker"]
        let insightsLoading = app.descendants(matching: .any)["insights.loading"]
        let insightsReady =
            insightsRoot.waitForExistence(timeout: 15)
            || insightsRange.waitForExistence(timeout: 5)
            || insightsLoading.waitForExistence(timeout: 5)
        XCTAssertTrue(insightsReady, "Insights screen should appear")

        // Transactions list
        app.tabBars.buttons["Transactions"].tap()
        let list = app.descendants(matching: .any)["transactions.list"]
        let empty = app.descendants(matching: .any)["transactions.empty"]
        let listReady = list.waitForExistence(timeout: 15) || empty.waitForExistence(timeout: 5)
        XCTAssertTrue(listReady, "Transactions list or empty state should appear")

        if list.exists {
            let firstRow = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "transactions.row."))
                .firstMatch
            if firstRow.waitForExistence(timeout: 8) {
                firstRow.tap()
                let category = app.descendants(matching: .any)["transactions.editor.category"]
                XCTAssertTrue(
                    category.waitForExistence(timeout: 10),
                    "Transaction editor category control should open"
                )
            }
        }
    }
}

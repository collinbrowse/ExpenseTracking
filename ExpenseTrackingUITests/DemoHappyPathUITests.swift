import XCTest

/// Demo happy-path smoke: onboarding → Home net/chart → Insights → Transactions.
final class DemoHappyPathUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDemoHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTesting",
            "-AppleLanguages", "(en)",
        ]
        app.launch()

        let demoButton = app.buttons["onboarding.demo"]
        XCTAssertTrue(
            demoButton.waitForExistence(timeout: 20),
            "Onboarding Demo button should appear on a fresh UITest launch"
        )
        demoButton.tap()

        // loadDemo is async (wipe + sync); wait until the sheet finishes and dismisses.
        XCTAssertTrue(
            demoButton.waitForNonExistence(timeout: 90),
            "Onboarding should dismiss after Demo finishes loading"
        )

        // Post-sync cleanup prompt can cover Home on CI; dismiss if present.
        let notNow = app.buttons["enrichment.notNow"]
        if notNow.waitForExistence(timeout: 8) {
            notNow.tap()
        } else {
            let labeledNotNow = app.buttons["Not Now"]
            if labeledNotNow.waitForExistence(timeout: 2) {
                labeledNotNow.tap()
            }
        }

        // Ensure Home is the visible tab (sheet dismissal can leave focus elsewhere).
        let homeTab = app.tabBars.buttons["Home"]
        if homeTab.waitForExistence(timeout: 5) {
            homeTab.tap()
        }

        let net = app.descendants(matching: .any)["home.net"]
        let loading = app.descendants(matching: .any)["home.loading"]
        if loading.waitForExistence(timeout: 3) {
            _ = loading.waitForNonExistence(timeout: 45)
        }
        XCTAssertTrue(
            net.waitForExistence(timeout: 45),
            "Home net should appear after Demo load"
        )

        let chart = app.descendants(matching: .any)["home.chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 15), "Home chart should be present")

        app.tabBars.buttons["Insights"].tap()
        let insightsRoot = app.descendants(matching: .any)["insights.root"]
        let insightsRange = app.descendants(matching: .any)["insights.rangePicker"]
        let insightsLoading = app.descendants(matching: .any)["insights.loading"]
        let insightsReady =
            insightsRoot.waitForExistence(timeout: 20)
            || insightsRange.waitForExistence(timeout: 10)
            || insightsLoading.waitForExistence(timeout: 10)
        XCTAssertTrue(insightsReady, "Insights screen should appear")

        app.tabBars.buttons["Transactions"].tap()
        let list = app.descendants(matching: .any)["transactions.list"]
        let empty = app.descendants(matching: .any)["transactions.empty"]
        let listReady = list.waitForExistence(timeout: 20) || empty.waitForExistence(timeout: 5)
        XCTAssertTrue(listReady, "Transactions list or empty state should appear")

        if list.exists {
            let firstRow = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "transactions.row."))
                .firstMatch
            if firstRow.waitForExistence(timeout: 10) {
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

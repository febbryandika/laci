import XCTest

/// SPEC §14: Settings › Diagnostik answers a WhatsApp support question on one screen, and offers
/// the log. The values are unit-tested; this proves the screen is reachable and complete.
final class DiagnosticsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDiagnosticsScreenShowsEveryFieldAndTheLog() {
        let app = UITestApp.launch()
        push(app, "SellView.settings", title: "Pengaturan")
        let diagnostics = app.buttons["SettingsView.diagnostics"]
        scrollTo(app, diagnostics)
        tap(diagnostics, "SettingsView.diagnostics") { app.navigationBars["Diagnostik"].exists }

        let rows = [
            "appVersion", "osVersion", "printer", "mtu", "lastPrint", "printDuration", "camera", "salesCount",
            "storeSize", "lastBackup", "schema",
        ]
        for row in rows {
            let field = element(app, "DiagnosticsView.\(row)")
            scrollTo(app, field)
            XCTAssertTrue(field.exists, row)
        }
        // The fixture store has had no sale yet, and nothing was ever backed up.
        XCTAssertTrue(element(app, "DiagnosticsView.salesCount").label.hasSuffix("0"))
        XCTAssertTrue(element(app, "DiagnosticsView.lastBackup").label.contains("Belum pernah"))

        let share = element(app, "DiagnosticsView.shareLog")
        scrollTo(app, share)
        XCTAssertTrue(share.isEnabled)
    }
}

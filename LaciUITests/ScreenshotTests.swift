import XCTest

/// Every screen in every language at the default and the largest text size (SPEC §9 verification).
/// Skipped unless `scripts/screenshots.sh` asks for it: the PNGs are the deliverable, not a pass.
final class ScreenshotTests: XCTestCase {
    private static let environment = ProcessInfo.processInfo.environment

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(Self.environment["LACI_SCREENSHOTS"] == "1", "set LACI_SCREENSHOTS=1 to record")
    }

    @MainActor
    func testScreenshotsAtDefaultSize() throws {
        for language in UITestApp.Language.allCases {
            try record(language: language, size: nil)
        }
    }

    @MainActor
    func testScreenshotsAtAX5() throws {
        for language in UITestApp.Language.allCases {
            try record(language: language, size: UITestApp.ax5)
        }
    }

    @MainActor
    private func record(language: UITestApp.Language, size: String?) throws {
        let app = UITestApp.launch(UITestApp.Options(contentSize: size, language: language))
        let sizeName = size == nil ? "default" : "ax5"
        func shot(_ screen: String) throws {
            try save("\(language.rawValue)-\(sizeName)-\(screen)")
        }
        XCTAssertTrue(app.buttons["SellView.scan"].waitForExistence(timeout: 5))
        try shot("sell-empty")
        _ = openScannerSheet(app, language: language)
        try shot("scanner")
        tap(app.buttons["ScannerSheet.close"], "close") { !app.navigationBars[language.scanTitle].exists }
        scan(app, code: UITestApp.fixtureBarcode, language: language)
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
        try shot("sell-cart")
        if !element(app, "SellView.tenderPane").exists {
            openTender(app, language: language)
            try shot("tender")
            app.navigationBars.buttons.firstMatch.tap()
        }
        tap(app.buttons["SellView.closeOut"], "closeOut") { app.textFields["CloseOutView.counted"].exists }
        try shot("closeout")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["SellView.history"], "history") { self.element(app, "SalesHistoryView.list").exists }
        try shot("history")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["SellView.stocktake"], "stocktake") { app.buttons["StocktakeView.scan"].exists }
        try shot("stocktake")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["SellView.settings"], "settings") { app.buttons["SettingsView.backupNow"].exists }
        try shot("settings")
        tap(app.buttons["SettingsView.catalogue"], "catalogue") { self.element(app, "CatalogueView.list").exists }
        try shot("catalogue")
        app.navigationBars.buttons.firstMatch.tap()
        let unlock = app.buttons["SettingsView.unlock"]
        scrollTo(app, unlock)
        tap(unlock, "unlock") { app.buttons["PaywallView.close"].exists }
        try shot("paywall")
        app.buttons["PaywallView.close"].tap()
        app.terminate()
    }

    /// Written to the host directory the script names and attached to the result bundle.
    @MainActor
    private func save(_ name: String) throws {
        let idiom = UITestApp.isPad ? "ipad" : "iphone"
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(idiom)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = Self.environment["LACI_SCREENSHOT_DIR"] else { return }
        let folder = URL(filePath: directory).appending(path: idiom)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: folder.appending(path: "\(name).png"))
    }
}

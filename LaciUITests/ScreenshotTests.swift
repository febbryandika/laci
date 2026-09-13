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

    /// Three launches per language and size: a pushed screen whose bar carries toolbar buttons has
    /// no reliable back button to tap, so each group ends with the app terminated instead.
    @MainActor
    private func record(language: UITestApp.Language, size: String?) throws {
        let sizeName = size == nil ? "default" : "ax5"
        let options = UITestApp.Options(contentSize: size, language: language)
        func shot(_ screen: String) throws {
            try save("\(language.rawValue)-\(sizeName)-\(screen)")
        }

        var app = UITestApp.launch(options)
        XCTAssertTrue(app.buttons["SellView.scan"].waitForExistence(timeout: 15))
        try shot("sell-empty")
        _ = openScannerSheet(app, language: language)
        try shot("scanner")
        tap(app.buttons["ScannerSheet.close"], "close") { !app.navigationBars[language.scanTitle].exists }
        scan(app, code: UITestApp.fixtureBarcode, language: language)
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
        try shot("sell-cart")
        openTender(app, language: language)
        if !element(app, "SellView.tenderPane").exists {
            try shot("tender")
        }
        let newSale = app.buttons["TenderView.newSale"]
        tap(app.buttons["Tender.chip.5000"], "chip") { newSale.exists }
        try shot("tender-completed")
        tap(newSale, "TenderView.newSale") { !newSale.exists }
        XCTAssertTrue(app.buttons["SellView.reprint"].waitForExistence(timeout: 10))
        try shot("sell-print-failed")
        tap(app.buttons["SellView.history"], "history") { self.element(app, "SalesHistoryView.list").exists }
        try shot("history")
        app.navigationBars.buttons.firstMatch.tap()
        tap(app.buttons["SellView.closeOut"], "closeOut") { app.textFields["CloseOutView.counted"].exists }
        try shot("closeout")
        app.terminate()

        app = UITestApp.launch(options)
        XCTAssertTrue(app.buttons["SellView.stocktake"].waitForExistence(timeout: 15))
        tap(app.buttons["SellView.stocktake"], "stocktake") { app.buttons["StocktakeView.scan"].exists }
        try shot("stocktake")
        app.terminate()

        try recordSettings(options, shot: shot)
    }

    @MainActor
    private func recordSettings(_ options: UITestApp.Options, shot: (String) throws -> Void) throws {
        let app = UITestApp.launch(options)
        XCTAssertTrue(app.buttons["SellView.settings"].waitForExistence(timeout: 15))
        // The first row: a Form lays out only what is on screen, and the backup rows are below it.
        tap(app.buttons["SellView.settings"], "settings") { app.buttons["SettingsView.catalogue"].exists }
        try shot("settings")
        let unlock = app.buttons["SettingsView.unlock"]
        scrollTo(app, unlock)
        tap(unlock, "unlock") { app.buttons["PaywallView.close"].exists }
        try shot("paywall")
        tap(app.buttons["PaywallView.close"], "close paywall") { !app.buttons["PaywallView.close"].exists }
        let catalogue = app.buttons["SettingsView.catalogue"]
        for _ in 0 ..< 6 where !(catalogue.exists && catalogue.isHittable) {
            app.swipeDown(velocity: .slow)
        }
        tap(catalogue, "catalogue") { self.element(app, "CatalogueView.list").exists }
        try shot("catalogue")
        app.terminate()
    }

    /// Written to the host directory the script names and attached to the result bundle.
    @MainActor
    private func save(_ name: String) throws {
        let idiom = UITestApp.isPad ? "ipad" : "iphone"
        // Existence fires while a push or a sheet is still sliding in.
        Thread.sleep(forTimeInterval: 0.8)
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

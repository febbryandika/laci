import XCTest

/// SPEC §15: the nephew can sell, the nephew cannot see margins. The simulator has no enrolled
/// biometrics and the launch states none, so these walk the PIN path of the gate.
final class OwnerGateTests: XCTestCase {
    private let pin = "123456"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchLocked(graceSeconds: Int? = nil) -> XCUIApplication {
        UITestApp.launch(UITestApp.Options(enforcesLock: true, lockGraceSeconds: graceSeconds))
    }

    /// Sets the first PIN through Settings and returns to the sell screen, which locks again.
    @MainActor
    private func launchWithPIN(graceSeconds: Int? = nil) -> XCUIApplication {
        let app = launchLocked(graceSeconds: graceSeconds)
        push(app, "SellView.settings", title: "Pengaturan")
        createPIN(app, pin)
        XCTAssertTrue(app.buttons["SettingsView.export"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["SellView.settings"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    func testSellingNeverAsksForThePIN() {
        let app = launchWithPIN()
        ringUpFixtureSale(app)
        XCTAssertFalse(app.secureTextFields["PINFlowView.field"].exists)
    }

    /// Every door to a margin, on the toolbar the device family has.
    @MainActor
    func testEveryOwnerScreenAsksForThePIN() {
        let app = launchWithPIN()
        var doors = [("SellView.closeOut", "Tutup kas"), ("SellView.stocktake", "Stok opname")]
        doors.append(("SellView.settings", "Pengaturan"))
        if UITestApp.isPad {
            doors.append(("SellView.catalogue", "Katalog"))
        }
        for (identifier, title) in doors {
            push(app, identifier, title: title)
            XCTAssertTrue(app.secureTextFields["PINFlowView.field"].waitForExistence(timeout: 5), identifier)
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testHistoryStaysOpenForReprinting() {
        let app = launchWithPIN()
        app.buttons["SellView.history"].tap()
        XCTAssertTrue(app.navigationBars["Riwayat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["PINFlowView.field"].exists)
    }

    @MainActor
    func testWrongPINStaysLockedAndTheRightOneOpens() {
        let app = launchWithPIN()
        push(app, "SellView.closeOut", title: "Tutup kas")
        enterPIN(app, "000000")
        XCTAssertTrue(element(app, "PINFlowView.notice").waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["CloseOutView.counted"].exists)
        enterPIN(app, pin)
        XCTAssertTrue(app.textFields["CloseOutView.counted"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLeavingLocksAgain() {
        let app = launchWithPIN()
        push(app, "SellView.closeOut", title: "Tutup kas")
        enterPIN(app, pin)
        XCTAssertTrue(app.textFields["CloseOutView.counted"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        push(app, "SellView.closeOut", title: "Tutup kas")
        XCTAssertTrue(app.secureTextFields["PINFlowView.field"].waitForExistence(timeout: 5))
    }

    /// Coming back inside the grace period keeps the screen and what was typed into it: a quick
    /// look at WhatsApp must not cost a stocktake or a typed count.
    @MainActor
    func testReturningInsideTheGracePeriodKeepsTheScreenAndItsContents() {
        let app = launchWithPIN()
        push(app, "SellView.closeOut", title: "Tutup kas")
        enterPIN(app, pin)
        let counted = app.textFields["CloseOutView.counted"]
        XCTAssertTrue(counted.waitForExistence(timeout: 5))
        counted.tap()
        counted.typeText("3500")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(counted.waitForExistence(timeout: 10))
        XCTAssertEqual(counted.value as? String, "3500")
        XCTAssertFalse(app.secureTextFields["PINFlowView.field"].exists)
    }

    /// Past the grace period the owner screen is gone, including one pushed on top of it. The grace
    /// is zero here, because the real minute is too long to wait out; `OwnerRelockTests` covers it.
    @MainActor
    func testReturningAfterTheGracePeriodLocksEvenFromAScreenPushedOnTop() {
        let app = launchWithPIN(graceSeconds: 0)
        push(app, "SellView.settings", title: "Pengaturan")
        enterPIN(app, pin)
        let export = app.buttons["SettingsView.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        scrollTo(app, export)
        export.tap()
        XCTAssertTrue(app.navigationBars["Ekspor CSV"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.buttons["SellView.settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Ekspor CSV"].exists)
        push(app, "SellView.settings", title: "Pengaturan")
        XCTAssertTrue(app.secureTextFields["PINFlowView.field"].waitForExistence(timeout: 5))
    }

    /// The requirement: a forgotten PIN does not lock the owner out of their own sales data.
    @MainActor
    func testForgottenPINStillReachesExport() {
        let app = launchWithPIN()
        ringUpFixtureSale(app)
        push(app, "SellView.settings", title: "Pengaturan")
        tap(app.buttons["OwnerGate.forgot"], "forgot") { app.navigationBars["Lupa PIN"].exists }
        tap(app.buttons["ForgotPINView.export"], "export") { app.navigationBars["Ekspor CSV"].exists }
        XCTAssertTrue(app.buttons["ExportView.sales"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ExportView.sale_lines"].exists)
        XCTAssertTrue(app.buttons["ExportView.close_outs"].exists)
    }

    @MainActor
    func testChangePINNeedsTheCurrentOne() {
        let app = launchWithPIN()
        push(app, "SellView.settings", title: "Pengaturan")
        enterPIN(app, pin)
        let change = app.buttons["SettingsView.changePIN"]
        scrollTo(app, change)
        tap(change, "change") { app.navigationBars["Ubah PIN"].exists }
        enterPIN(app, "000000")
        XCTAssertTrue(element(app, "PINFlowView.notice").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "PINFlowView.prompt.current").exists)
        enterPIN(app, pin)
        createPIN(app, "654321")
        XCTAssertTrue(app.navigationBars["Pengaturan"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        push(app, "SellView.closeOut", title: "Tutup kas")
        enterPIN(app, pin)
        XCTAssertTrue(element(app, "PINFlowView.notice").waitForExistence(timeout: 5))
        enterPIN(app, "654321")
        XCTAssertTrue(app.textFields["CloseOutView.counted"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testResetPINNeedsTheCurrentOneThenAsksForANewPIN() {
        let app = launchWithPIN()
        push(app, "SellView.settings", title: "Pengaturan")
        enterPIN(app, pin)
        let reset = app.buttons["SettingsView.resetPIN"]
        scrollTo(app, reset)
        tap(reset, "reset") { app.navigationBars["Reset PIN"].exists }
        enterPIN(app, "000000")
        XCTAssertTrue(element(app, "PINFlowView.notice").waitForExistence(timeout: 5))
        enterPIN(app, pin)
        XCTAssertTrue(app.navigationBars["Pengaturan"].waitForExistence(timeout: 5))
        let create = app.buttons["SettingsView.createPIN"]
        scrollTo(app, create)
        app.navigationBars.buttons.firstMatch.tap()

        push(app, "SellView.closeOut", title: "Tutup kas")
        XCTAssertTrue(element(app, "PINFlowView.prompt.new").waitForExistence(timeout: 5))
    }
}

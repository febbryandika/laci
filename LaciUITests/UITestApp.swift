import UIKit
import XCTest

/// Every UI test launches through here (SPEC §11): an in-memory store seeded with the real
/// catalogue, settings wiped, and never the on-disk store. The keys are read by `LaunchEnvironment`
/// in the app, DEBUG builds only.
enum UITestApp {
    struct Options {
        var offline = false
        var emptyCatalogue = false
        /// A `UIContentSizeCategory` raw value, applied through the launch argument iOS reads.
        var contentSize: String?
        var trialLimit: Int?
    }

    /// `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`: SPEC §9 names it by its long form,
    /// `UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge`; this is that constant.
    static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    /// Row W001 of warung-200: Indomie Goreng 85g, Rp 3.500, EAN-13.
    static let fixtureBarcode = "8991128170404"
    static let fixtureName = "Indomie Goreng 85g"

    @MainActor
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    @MainActor
    static func launch(_ options: Options = Options()) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LACI_UI_TESTING"] = "1"
        if options.emptyCatalogue {
            app.launchEnvironment["LACI_UI_EMPTY"] = "1"
        }
        if options.offline {
            app.launchEnvironment["LACI_OFFLINE"] = "1"
        }
        if let limit = options.trialLimit {
            app.launchEnvironment["LACI_TRIAL_SALE_LIMIT"] = String(limit)
        }
        if let size = options.contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        return app
    }
}

extension XCTestCase {
    /// Opens the scan sheet and returns the manual-entry field once the sheet has settled. The
    /// simulator has no camera but does ask for permission on first use, and an interruption
    /// monitor only runs on an interaction, so the wait taps the bar between checks: the alert can
    /// land before or after any single tap.
    @MainActor
    func openScannerSheet(_ app: XCUIApplication) -> XCUIElement {
        addUIInterruptionMonitor(withDescription: "Camera permission") { alert in
            let allow = alert.buttons.element(boundBy: alert.buttons.count - 1)
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        let scan = app.buttons["SellView.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        let bar = app.navigationBars["Pindai"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let entry = app.textFields["ScannerSheet.manualEntry"]
        for _ in 0 ..< 15 where !entry.exists {
            bar.tap()
            _ = entry.waitForExistence(timeout: 1)
        }
        return entry
    }

    /// Types a code into the scan sheet's manual entry, which is the same path a camera read takes,
    /// and closes the sheet.
    @MainActor
    func scan(_ app: XCUIApplication, code: String) {
        let entry = openScannerSheet(app)
        XCTAssertTrue(entry.exists)
        entry.tap()
        entry.typeText(code + "\n")
        app.buttons["ScannerSheet.close"].tap()
    }

    /// Ten digits: not an EAN shape, so it is looked up as-is and is unknown, and digits only, so
    /// the software keyboard CI types on needs no plane switching.
    func unknownCode() -> String {
        "77\(Int.random(in: 10_000_000 ... 99_999_999))"
    }
}

import UIKit
import XCTest

/// Every UI test launches through here (SPEC §11): an in-memory store seeded with the real
/// catalogue, settings wiped, and never the on-disk store. The keys are read by `LaunchEnvironment`
/// in the app, DEBUG builds only.
enum UITestApp {
    /// The three UI languages. Every launch pins one, because the simulator's own language is
    /// English and the assertions read Indonesian copy.
    enum Language: String, CaseIterable {
        case indonesian = "id"
        case english = "en"
        case japanese = "ja"

        var locale: String {
            switch self {
            case .indonesian: "id_ID"
            case .english: "en_US"
            case .japanese: "ja_JP"
            }
        }

        /// The two navigation titles the shared helpers wait for.
        var scanTitle: String {
            switch self {
            case .indonesian: "Pindai"
            case .english: "Scan"
            case .japanese: "スキャン"
            }
        }

        var payTitle: String {
            switch self {
            case .indonesian: "Bayar"
            case .english: "Pay"
            case .japanese: "会計"
            }
        }
    }

    struct Options {
        var offline = false
        var emptyCatalogue = false
        /// A `UIContentSizeCategory` raw value, applied through the launch argument iOS reads.
        var contentSize: String?
        var trialLimit: Int?
        /// UI language and device locale together, so money and dates are checked against a
        /// device that would format them differently.
        var language: Language = .indonesian
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
        app.launchArguments += [
            "-AppleLanguages", "(\(options.language.rawValue))", "-AppleLocale", options.language.locale,
        ]
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
    func openScannerSheet(_ app: XCUIApplication, language: UITestApp.Language = .indonesian) -> XCUIElement {
        addUIInterruptionMonitor(withDescription: "Camera permission") { alert in
            let allow = alert.buttons.element(boundBy: alert.buttons.count - 1)
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        let scan = app.buttons["SellView.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        let bar = app.navigationBars[language.scanTitle]
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
    func scan(_ app: XCUIApplication, code: String, language: UITestApp.Language = .indonesian) {
        let entry = openScannerSheet(app, language: language)
        XCTAssertTrue(entry.exists)
        entry.tap()
        entry.typeText(code + "\n")
        tap(app.buttons["ScannerSheet.close"], "ScannerSheet.close") {
            !app.navigationBars[language.scanTitle].exists
        }
    }

    /// Ten digits: not an EAN shape, so it is looked up as-is and is unknown, and digits only, so
    /// the software keyboard CI types on needs no plane switching.
    func unknownCode() -> String {
        "77\(Int.random(in: 10_000_000 ... 99_999_999))"
    }

    /// Every tap goes through here. A tap synthesized while a sheet is still sliding away is
    /// dropped by SwiftUI and XCTest does not count that moment as busy, so a tap that has an
    /// observable outcome states it and is retried until the outcome shows.
    @MainActor
    func tap(
        _ element: XCUIElement, _ name: String = "", attempts: Int = 3, until outcome: (() -> Bool)? = nil
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), name)
        for _ in 0 ..< 10 where !element.isHittable {
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard let outcome else {
            element.tap()
            return
        }
        for attempt in 1 ... attempts {
            element.tap()
            for _ in 0 ..< 15 {
                if outcome() {
                    return
                }
                Thread.sleep(forTimeInterval: 0.2)
            }
            XCTContext.runActivity(named: "tap \(name) attempt \(attempt) had no effect") { _ in }
        }
        XCTFail("\(name): no effect after \(attempts) taps")
    }

    /// A toolbar button that pushes a screen with the given title.
    @MainActor
    func push(_ app: XCUIApplication, _ identifier: String, title: String) {
        tap(app.buttons[identifier], identifier) { app.navigationBars[title].exists }
    }

    /// Any element by identifier, whatever its type: a Section, a DisclosureGroup or a Picker
    /// does not surface as a button.
    @MainActor
    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls a form in small steps until the element is on screen, as a List only lays out the
    /// rows it shows.
    @MainActor
    func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0 ..< 6 where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
    }

    /// The keypad is a pane on an iPad and a sheet behind Bayar on an iPhone; after this the tender
    /// controls are on screen either way.
    @MainActor
    func openTender(_ app: XCUIApplication, language: UITestApp.Language = .indonesian) {
        if element(app, "SellView.tenderPane").exists {
            return
        }
        tap(app.buttons["SellView.pay"], "SellView.pay") { app.navigationBars[language.payTitle].exists }
    }

    /// Scans the fixture item, pays with a quick-tender chip and starts the next sale.
    @MainActor
    func ringUpFixtureSale(_ app: XCUIApplication, chip: String = "5000", language: UITestApp.Language = .indonesian) {
        scan(app, code: UITestApp.fixtureBarcode, language: language)
        XCTAssertTrue(app.buttons["SellView.line.W001"].waitForExistence(timeout: 5))
        openTender(app, language: language)
        let newSale = app.buttons["TenderView.newSale"]
        tap(app.buttons["Tender.chip.\(chip)"], "chip \(chip)") { newSale.exists }
        tap(newSale, "TenderView.newSale") { !newSale.exists }
        XCTAssertTrue(app.navigationBars[language.payTitle].waitForNonExistence(timeout: 5))
    }

    /// The first close-out of a fresh store: the opening float is asked for.
    @MainActor
    func openCloseOut(_ app: XCUIApplication, openingFloat: String, counted: String) {
        push(app, "SellView.closeOut", title: "Tutup kas")
        let opening = app.textFields["CloseOutView.openingFloat"]
        XCTAssertTrue(opening.waitForExistence(timeout: 5))
        opening.tap()
        opening.typeText(openingFloat)
        let countedField = app.textFields["CloseOutView.counted"]
        countedField.tap()
        countedField.typeText(counted)
    }
}

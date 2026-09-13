import XCTest

/// SPEC §9: an empty catalogue offers import and add-first-product and nothing else; the catalogue
/// screen is a list with an inspector beside it on an iPad and pushed on an iPhone.
final class CatalogueTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyCatalogueOffersImportAndFirstProductOnly() {
        let app = UITestApp.launch(UITestApp.Options(emptyCatalogue: true))
        let addFirst = app.buttons["Catalogue.addFirst"]
        XCTAssertTrue(addFirst.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Catalogue.importCSV"].exists)
        XCTAssertFalse(app.textFields["SellView.search"].exists, "nothing else")
        addFirst.tap()
        XCTAssertTrue(app.navigationBars["Produk baru"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "NewProductView.barcode").exists)
        let sku = app.textFields["NewProductView.sku"]
        sku.tap()
        sku.typeText("A1")
        let name = app.textFields["NewProductView.name"]
        name.tap()
        name.typeText("Aqua")
        let price = app.textFields["NewProductView.price"]
        price.tap()
        price.typeText("3500")
        app.buttons["NewProductView.save"].tap()
        XCTAssertTrue(app.buttons["SellView.line.A1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Catalogue.addFirst"].exists)
    }

    @MainActor
    func testCatalogueScreenShowsTheInspector() {
        let app = UITestApp.launch()
        if UITestApp.isPad {
            push(app, "SellView.catalogue", title: "Katalog")
        } else {
            push(app, "SellView.settings", title: "Pengaturan")
            push(app, "SettingsView.catalogue", title: "Katalog")
        }
        let row = app.buttons["CatalogueView.row.W001"]
        if !row.waitForExistence(timeout: 2) {
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("Indomie Goreng")
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let sku = app.staticTexts["CatalogueInspectorView.sku"]
        XCTAssertTrue(sku.waitForExistence(timeout: 5))
        // A Form row reads its label and value as one: "SKU, W001".
        XCTAssertTrue(sku.label.hasSuffix("W001"), sku.label)
    }
}

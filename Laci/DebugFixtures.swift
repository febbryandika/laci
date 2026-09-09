#if DEBUG
    import Foundation
    import LaciCore

    /// Loads the bundled seed catalogue (SPEC §12) so every screen is built against real-shaped data.
    /// Debug builds only; the Settings action that calls it arrives with the Settings screen.
    enum DebugFixtures {
        struct Load {
            let added: Int
            let updated: Int
            let rejected: Int
        }

        enum Failure: Error {
            case fixtureMissing
        }

        @MainActor
        static func loadWarung200(into dependencies: Dependencies, now: Date = .now) throws -> Load {
            guard let url = Bundle.main.url(forResource: "warung-200", withExtension: "csv") else {
                throw Failure.fixtureMissing
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            let importer = CatalogueImporter(
                products: dependencies.products, stock: dependencies.stock, transactor: dependencies.transactor
            )
            let preview = try importer.preview(CatalogueCSV.parse(text))
            try importer.commit(preview, now: now)
            return Load(added: preview.added.count, updated: preview.updated.count, rejected: preview.rejected.count)
        }
    }
#endif

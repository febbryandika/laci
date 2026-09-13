import Foundation
import LaciCore
import Observation

/// Preview-then-commit over `CatalogueImporter` (SPEC §3.2): the file is classified row by row
/// before anything is written, and the whole preview is applied or nothing is. The URL read is
/// kept apart from `preview(text:)` so the classification is tested without a file.
@MainActor
@Observable
final class CatalogueImportViewModel {
    enum Phase: Hashable {
        case picking
        case previewed(ImportPreview)
        case failed(String)
        case done(added: Int, updated: Int)
    }

    private(set) var phase: Phase = .picking

    private let importer: CatalogueImporter
    private let delimiter: Character
    private let now: () -> Date

    init(
        dependencies: Dependencies, delimiter: Character = ExportSettings.delimiter(),
        now: @escaping () -> Date = { Date() }
    ) {
        importer = CatalogueImporter(
            products: dependencies.products, stock: dependencies.stock, transactor: dependencies.transactor
        )
        self.delimiter = delimiter
        self.now = now
    }

    func read(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return fail("Berkas tidak bisa dibaca sebagai teks UTF-8")
        }
        preview(text: text)
    }

    func preview(text: String) {
        do {
            let parsed = try CatalogueCSV.parse(text, delimiter: delimiter)
            phase = try .previewed(importer.preview(parsed))
        } catch let error as CatalogueCSV.ParseError {
            fail(ImportErrorText.label(error))
        } catch {
            fail("Katalog tidak bisa dibaca")
        }
    }

    func commit() {
        guard case let .previewed(preview) = phase else { return }
        do {
            try importer.commit(preview, now: now())
            phase = .done(added: preview.added.count, updated: preview.updated.count)
        } catch {
            fail("Gagal menyimpan impor, tidak ada yang diubah")
        }
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }

    func reset() {
        phase = .picking
    }
}

/// One wording per way a file can be refused.
enum ImportErrorText {
    static func label(_ error: CatalogueCSV.ParseError) -> String {
        switch error {
        case .emptyFile: "Berkas kosong"
        case let .headerMismatch(found):
            "Kolom tidak sesuai. Diharapkan: \(CatalogueCSV.columns.joined(separator: ", ")). "
                + "Ditemukan: \(found.joined(separator: ", "))"
        case let .unterminatedQuote(line): "Tanda kutip tidak ditutup di baris \(line)"
        }
    }

    static func label(_ reason: ImportRejection.Reason) -> String {
        switch reason {
        case let .malformed(detail): "Baris rusak: \(detail)"
        case .duplicateSKUInFile: "SKU muncul dua kali dalam berkas"
        case let .barcodeDuplicatedInFile(value): "Barcode \(value) muncul dua kali dalam berkas"
        case let .invalidBarcode(value): "Barcode \(value) tidak valid"
        case let .barcodeTaken(value, sku): "Barcode \(value) sudah dipakai SKU \(sku)"
        }
    }
}

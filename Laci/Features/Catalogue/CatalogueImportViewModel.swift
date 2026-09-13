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
        case failed(ImportFailure)
        case done(added: Int, updated: Int)
    }

    /// Why a file was refused, as a case: the wording lives in the catalog, and the phase stays
    /// `Hashable` (a `LocalizedStringResource` is not).
    enum ImportFailure: Hashable {
        case unopenable
        case notUTF8
        case parse(CatalogueCSV.ParseError)
        case unreadable
        case commitFailed

        var message: LocalizedStringResource {
            switch self {
            case .unopenable: "Berkas tidak bisa dibuka"
            case .notUTF8: "Berkas tidak bisa dibaca sebagai teks UTF-8"
            case let .parse(error): ImportErrorText.label(error)
            case .unreadable: "Katalog tidak bisa dibaca"
            case .commitFailed: "Gagal menyimpan impor, tidak ada yang diubah"
            }
        }
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
            return fail(.notUTF8)
        }
        preview(text: text)
    }

    func preview(text: String) {
        do {
            let parsed = try CatalogueCSV.parse(text, delimiter: delimiter)
            phase = try .previewed(importer.preview(parsed))
        } catch let error as CatalogueCSV.ParseError {
            fail(.parse(error))
        } catch {
            fail(.unreadable)
        }
    }

    func commit() {
        guard case let .previewed(preview) = phase else { return }
        do {
            try importer.commit(preview, now: now())
            phase = .done(added: preview.added.count, updated: preview.updated.count)
        } catch {
            fail(.commitFailed)
        }
    }

    func fail(_ failure: ImportFailure) {
        phase = .failed(failure)
    }

    func reset() {
        phase = .picking
    }
}

/// One wording per way a file can be refused. Whole sentences with the column lists as arguments,
/// never two halves joined: a translator sees the sentence.
enum ImportErrorText {
    static func label(_ error: CatalogueCSV.ParseError) -> LocalizedStringResource {
        switch error {
        case .emptyFile:
            return "Berkas kosong"
        case let .headerMismatch(found):
            let expected = CatalogueCSV.columns.joined(separator: ", ")
            let actual = found.joined(separator: ", ")
            return "Kolom tidak sesuai. Diharapkan: \(expected). Ditemukan: \(actual)"
        case let .unterminatedQuote(line):
            return "Tanda kutip tidak ditutup di baris \(line)"
        }
    }

    static func label(_ reason: ImportRejection.Reason) -> LocalizedStringResource {
        switch reason {
        case let .malformed(detail): label(detail)
        case .duplicateSKUInFile: "SKU muncul dua kali dalam berkas"
        case let .barcodeDuplicatedInFile(value): "Barcode \(value) muncul dua kali dalam berkas"
        case let .invalidBarcode(value): "Barcode \(value) tidak valid"
        case let .barcodeTaken(value, sku): "Barcode \(value) sudah dipakai SKU \(sku)"
        }
    }

    static func label(_ reason: ImportRejection.MalformedReason) -> LocalizedStringResource {
        switch reason {
        case let .columnCount(expected, found): "Baris punya \(found) kolom, seharusnya \(expected)"
        case .emptySKU: "SKU kosong"
        case .emptyName: "Nama kosong"
        case .costNotDecimal: "Modal bukan angka"
        case .priceNotDecimal: "Harga jual bukan angka"
        case .tracksStockNotBool: "tracks_stock harus true atau false"
        case .stockNotDecimal: "Stok bukan angka"
        }
    }
}

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The file `.fileExporter` writes (SPEC §5.2). The text is the codec's; the BOM is added here,
/// once, because the accountant runs Excel on Windows and Excel reads a BOM-less UTF-8 file as
/// the local code page.
struct CSVExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    let text: String

    init(text: String) {
        self.text = text
    }

    /// The file's bytes with the BOM stripped, or nil when they are not UTF-8.
    init?(fileData data: Data) {
        let bytes = data.starts(with: Self.bom) ? data.dropFirst(Self.bom.count) : data[...]
        guard let text = String(data: bytes, encoding: .utf8) else { return nil }
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let document = CSVExportDocument(fileData: data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self = document
    }

    /// BOM first, then the text as UTF-8.
    var fileData: Data {
        var data = Data(Self.bom)
        data.append(Data(text.utf8))
        return data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: fileData)
    }
}

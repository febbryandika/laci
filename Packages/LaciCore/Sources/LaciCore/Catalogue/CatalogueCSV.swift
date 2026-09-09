import Foundation

/// One catalogue row as the CSV carries it. `line` is the physical 1-based line in the file, so a
/// rejection can point the owner at the row in their spreadsheet.
public struct CatalogueRow: Hashable, Sendable {
    public let line: Int
    public let sku: String
    public let name: String
    public let unit: String
    public let cost: Decimal
    public let price: Decimal
    public let tracksStock: Bool
    public let stockOnHand: Decimal
    public let barcodes: [String]

    public init(
        line: Int, sku: String, name: String, unit: String, cost: Decimal, price: Decimal, tracksStock: Bool,
        stockOnHand: Decimal, barcodes: [String]
    ) {
        self.line = line
        self.sku = sku
        self.name = name
        self.unit = unit
        self.cost = cost
        self.price = price
        self.tracksStock = tracksStock
        self.stockOnHand = stockOnHand
        self.barcodes = barcodes
    }
}

public struct ImportRejection: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        case malformed(String)
        case duplicateSKUInFile
        case barcodeDuplicatedInFile(value: String)
        case invalidBarcode(value: String)
        case barcodeTaken(value: String, bySKU: String)
    }

    public let line: Int
    public let sku: String?
    public let reason: Reason

    public init(line: Int, sku: String?, reason: Reason) {
        self.line = line
        self.sku = sku
        self.reason = reason
    }
}

/// The catalogue file format (SPEC §3.2, §5.2): a fixed header, `#` comment lines, RFC 4180 quoting,
/// pipe-separated barcodes, and money as unformatted decimal strings. No `FormatStyle` anywhere in
/// here: an `id_ID` formatter writes `15.000,00` and a spreadsheet reads that as fifteen.
public enum CatalogueCSV {
    public static let columns = ["sku", "name", "unit", "cost", "price", "tracks_stock", "stock_on_hand", "barcodes"]

    public enum ParseError: Error, Hashable, Sendable {
        case emptyFile
        case headerMismatch(found: [String])
        case unterminatedQuote(line: Int)
    }

    public struct Parsed: Hashable, Sendable {
        public let rows: [CatalogueRow]
        public let rejected: [ImportRejection]

        public init(rows: [CatalogueRow], rejected: [ImportRejection]) {
            self.rows = rows
            self.rejected = rejected
        }
    }

    public static func parse(_ text: String, delimiter: Character = ",") throws(ParseError) -> Parsed {
        var tokenizer = Tokenizer(text: text, delimiter: delimiter)
        let records = try tokenizer.run()
        guard let header = records.first else { throw .emptyFile }
        let found = header.fields.map { $0.trimmingCharacters(in: .whitespaces) }
        guard found == columns else { throw .headerMismatch(found: found) }

        var rows: [CatalogueRow] = []
        var rejected: [ImportRejection] = []
        for record in records.dropFirst() {
            switch decode(record) {
            case let .row(row): rows.append(row)
            case let .rejected(rejection): rejected.append(rejection)
            }
        }
        rows = rejectDuplicates(in: rows, rejected: &rejected)
        return Parsed(rows: rows, rejected: rejected.sorted { $0.line < $1.line })
    }

    public static func export(_ rows: [CatalogueRow], delimiter: Character = ",") -> String {
        var lines = [columns.joined(separator: String(delimiter))]
        for row in rows {
            let fields = [
                row.sku, row.name, row.unit, "\(row.cost)", "\(row.price)", row.tracksStock ? "true" : "false",
                "\(row.stockOnHand)", row.barcodes.joined(separator: "|"),
            ]
            lines.append(fields.map { quoteIfNeeded($0, delimiter: delimiter) }.joined(separator: String(delimiter)))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Decoding

    private static func decode(_ record: Record) -> Decoded {
        let fields = record.fields.map { $0.trimmingCharacters(in: .whitespaces) }
        let sku = fields.first.flatMap { $0.isEmpty ? nil : $0 }
        func reject(_ reason: ImportRejection.Reason) -> Decoded {
            .rejected(ImportRejection(line: record.line, sku: sku, reason: reason))
        }
        guard fields.count == columns.count else {
            return reject(.malformed("expected \(columns.count) columns, found \(fields.count)"))
        }
        guard let sku else { return reject(.malformed("sku is empty")) }
        guard !fields[1].isEmpty else { return reject(.malformed("name is empty")) }
        guard let cost = decimal(fields[3]) else { return reject(.malformed("cost is not a decimal")) }
        guard let price = decimal(fields[4]) else { return reject(.malformed("price is not a decimal")) }
        guard let tracksStock = bool(fields[5]) else { return reject(.malformed("tracks_stock is not true/false")) }
        guard let stock = decimal(fields[6]) else { return reject(.malformed("stock_on_hand is not a decimal")) }
        let barcodes = fields[7].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let bad = barcodes.first(where: { Symbology.inferred(from: $0) == nil }) {
            return reject(.invalidBarcode(value: bad))
        }
        return .row(CatalogueRow(
            line: record.line, sku: sku, name: fields[1], unit: fields[2], cost: cost, price: price,
            tracksStock: tracksStock, stockOnHand: stock, barcodes: barcodes
        ))
    }

    /// Strict: `Decimal(string:)` happily reads `12abc` as 12, so the shape is checked first.
    private static func decimal(_ text: String) -> Decimal? {
        guard text.wholeMatch(of: /-?\d+(?:\.\d+)?/) != nil, let value = Decimal(string: text), value >= 0 else {
            return nil
        }
        return value
    }

    private static func bool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "1": true
        case "false", "0": false
        default: nil
        }
    }

    /// A SKU or barcode that appears twice rejects every row carrying it: the file cannot say which
    /// one the owner meant.
    private static func rejectDuplicates(in rows: [CatalogueRow], rejected: inout [ImportRejection]) -> [CatalogueRow] {
        let skuCounts = Dictionary(rows.map { ($0.sku, 1) }, uniquingKeysWith: +)
        let unique = rows.filter { row in
            guard skuCounts[row.sku] == 1 else {
                rejected.append(ImportRejection(line: row.line, sku: row.sku, reason: .duplicateSKUInFile))
                return false
            }
            return true
        }
        let barcodeCounts = Dictionary(unique.flatMap(\.barcodes).map { ($0, 1) }, uniquingKeysWith: +)
        return unique.filter { row in
            guard let duplicate = row.barcodes.first(where: { barcodeCounts[$0, default: 0] > 1 }) else { return true }
            rejected.append(ImportRejection(
                line: row.line, sku: row.sku, reason: .barcodeDuplicatedInFile(value: duplicate)
            ))
            return false
        }
    }

    private static func quoteIfNeeded(_ field: String, delimiter: Character) -> String {
        guard field.contains(where: { $0 == delimiter || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

public extension Symbology {
    /// EAN by length and check digit; any other non-empty payload is treated as CODE-128. A digit-only
    /// EAN-length value with a bad check digit is nil: that is a typo, not a different symbology.
    static func inferred(from value: String) -> Symbology? {
        switch EAN.validate(value) {
        case let .valid(symbology): symbology
        case .badChecksum: nil
        case .notEAN: value.isEmpty ? nil : .code128
        }
    }
}

private enum Decoded {
    case row(CatalogueRow)
    case rejected(ImportRejection)
}

// MARK: - Tokenizer

private struct Record {
    let line: Int
    let fields: [String]
}

/// RFC 4180 over `Character`s: quoted fields may hold the delimiter, doubled quotes and newlines.
/// Swift reads CRLF as one `Character`, so both line endings are matched explicitly and a lone CR is
/// dropped. A `#` at the start of a line skips the line.
private struct Tokenizer {
    private let characters: [Character]
    private let delimiter: Character
    private var index = 0
    private var line = 1
    private var recordLine = 1
    private var field = ""
    private var fields: [String] = []
    private var records: [Record] = []
    private var inQuotes = false
    private var pendingQuote = false

    init(text: String, delimiter: Character) {
        characters = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        self.delimiter = delimiter
    }

    mutating func run() throws(CatalogueCSV.ParseError) -> [Record] {
        while index < characters.count {
            let character = characters[index]
            index += 1
            if inQuotes {
                quoted(character)
            } else {
                unquoted(character)
            }
        }
        if inQuotes, !pendingQuote {
            throw .unterminatedQuote(line: recordLine)
        }
        if !field.isEmpty || !fields.isEmpty {
            endRecord()
        }
        return records
    }

    private mutating func quoted(_ character: Character) {
        if pendingQuote {
            pendingQuote = false
            if character == "\"" {
                field.append("\"")
                return
            }
            inQuotes = false
            unquoted(character)
        } else if character == "\"" {
            pendingQuote = true
        } else {
            if character.isCSVNewline {
                line += 1
                field.append("\n")
            } else {
                field.append(character)
            }
        }
    }

    private mutating func unquoted(_ character: Character) {
        switch character {
        case "#" where field.isEmpty && fields.isEmpty:
            while index < characters.count, !characters[index].isCSVNewline {
                index += 1
            }
        case "\"":
            inQuotes = true
        case delimiter:
            fields.append(field)
            field = ""
        case "\r":
            break
        case "\n", "\r\n":
            endRecord()
            line += 1
            recordLine = line
        default:
            field.append(character)
        }
    }

    private mutating func endRecord() {
        fields.append(field)
        field = ""
        defer { fields = [] }
        guard fields != [""] else { return }
        records.append(Record(line: recordLine, fields: fields))
    }
}

private extension Character {
    var isCSVNewline: Bool {
        self == "\n" || self == "\r\n"
    }
}

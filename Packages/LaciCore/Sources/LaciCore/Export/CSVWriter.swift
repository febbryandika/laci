import Foundation

/// The one CSV writer (SPEC §5.2): RFC 4180 quoting, LF line endings, a trailing newline and no
/// BOM. The BOM belongs to the file the app writes, not to the text, so a codec test can compare
/// strings and the catalogue round-trip stays byte-exact.
enum CSVWriter {
    static func document(columns: [String], rows: [[String]], delimiter: Character) -> String {
        let separator = String(delimiter)
        var lines = [columns.joined(separator: separator)]
        lines.reserveCapacity(rows.count + 1)
        for row in rows {
            lines.append(row.map { quoteIfNeeded($0, delimiter: delimiter) }.joined(separator: separator))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func quoteIfNeeded(_ field: String, delimiter: Character) -> String {
        guard field.contains(where: { $0 == delimiter || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

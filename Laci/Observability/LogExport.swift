import CoreTransferable
import Foundation
import OSLog
import UniformTypeIdentifiers

/// One entry read back from the log store, reduced to values that can leave the reader.
nonisolated struct LogLine: Hashable, Sendable {
    let date: Date
    let level: String
    let category: String
    let message: String
}

/// The text of "Bagikan log" (SPEC §14): a header, then the last `limit` entries, oldest first.
nonisolated enum LogReport {
    static let limit = 500

    static func text(header: [String], lines: [LogLine], timeZone: TimeZone, limit: Int = limit) -> String {
        let time = Date.ISO8601FormatStyle(timeZone: timeZone).time(includingFractionalSeconds: true)
        let kept = lines.sorted { $0.date < $1.date }.suffix(limit)
        var out = header
        out.append("Entries: \(kept.count) of \(lines.count)")
        out.append("")
        out += kept.map { "\(time.format($0.date)) [\($0.category)] \($0.level): \($0.message)" }
        return out.joined(separator: "\n") + "\n"
    }
}

/// One piece of a logged message: the literal text before an argument, the argument's format
/// placeholder (which carries its privacy, e.g. `%{private}s`), and the argument rendered as text.
nonisolated struct LogPart: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case scalar
        case text
        case none
    }

    let literal: String
    let placeholder: String
    let kind: Kind
    let value: String?
}

/// Reads this process's own entries. On iOS `OSLogStore` sees only the current process, so a
/// shared log starts at the latest launch; a crash before it is Crashlytics' job, not this one's.
///
/// A process reading its own log gets `.private` values back in clear (`composedMessage` is not
/// redacted), so every message is rebuilt from its parts and anything not public is replaced.
nonisolated enum LogStoreReader {
    static let redacted = "<private>"

    static func entries(subsystem: String = Log.subsystem) throws -> [LogLine] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
        return entries.compactMap { entry in
            guard let log = entry as? OSLogEntryLog else { return nil }
            return LogLine(
                date: log.date, level: level(log.level), category: log.category,
                message: message(log.components.map(part))
            )
        }
    }

    /// The os rule, applied here because the store will not: an argument marked public is shown;
    /// one marked private is not; unmarked, scalars are shown and text is not.
    static func message(_ parts: [LogPart]) -> String {
        parts.map { part in
            guard part.kind != .none, !part.placeholder.isEmpty else { return part.literal }
            let isPublic = if part.placeholder.contains("private") {
                false
            } else if part.placeholder.contains("public") {
                true
            } else {
                part.kind == .scalar
            }
            return part.literal + (isPublic ? part.value ?? "" : redacted)
        }.joined()
    }

    private static func part(_ component: OSLogMessageComponent) -> LogPart {
        let kind: LogPart.Kind
        let value: String?
        switch component.argumentCategory {
        case .int64:
            kind = .scalar
            // A Bool is logged as an integer with a `bool` format modifier.
            value = component.placeholder.contains("bool")
                ? String(component.argumentInt64Value != 0) : String(component.argumentInt64Value)
        case .uInt64:
            kind = .scalar
            value = String(component.argumentUInt64Value)
        case .double:
            kind = .scalar
            value = String(component.argumentDoubleValue)
        case .string:
            kind = .text
            value = component.argumentStringValue
        case .data:
            kind = .text
            value = nil
        case .undefined:
            kind = .none
            value = nil
        @unknown default:
            kind = .text
            value = nil
        }
        return LogPart(literal: component.formatSubstring, placeholder: component.placeholder, kind: kind, value: value)
    }

    private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        case .undefined: "-"
        @unknown default: "-"
        }
    }
}

/// What the share sheet receives. Nothing is read or written until a destination asks for the
/// file, and the file holds no amount or product name: those were logged `.private`.
nonisolated struct SupportLog: Transferable {
    let header: [String]
    let timeZone: TimeZone
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { log in
            let lines = (try? LogStoreReader.entries()) ?? []
            let text = LogReport.text(header: log.header, lines: lines, timeZone: log.timeZone)
            let folder = FileManager.default.temporaryDirectory.appending(path: "laci-log-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: log.fileName)
            try Data(text.utf8).write(to: url)
            return SentTransferredFile(url)
        }
    }

    /// "laci-log-20261030-2003.txt", in the shop's zone.
    static func fileName(at date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(
            format: "%04d%02d%02d-%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0,
            parts.minute ?? 0
        )
        return "laci-log-\(stamp).txt"
    }
}

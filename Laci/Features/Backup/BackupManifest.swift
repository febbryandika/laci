import Foundation

/// What sits next to the store file in every archive: enough to show a list, refuse a backup
/// from another schema, and tell a shop owner what the backup holds.
nonisolated struct BackupManifest: Codable, Hashable, Sendable {
    struct File: Codable, Hashable, Sendable {
        let name: String
        let byteCount: Int
    }

    static let currentFormat = 1

    var formatVersion = BackupManifest.currentFormat
    let createdAt: Date
    let schemaVersion: String
    let appVersion: String
    let build: String
    let shopName: String
    let files: [File]

    static let fileName = "manifest.json"

    var byteCount: Int {
        files.reduce(0) { $0 + $1.byteCount }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupManifest.self, from: data)
    }
}

/// One archive in the container, as listed for the restore screen.
nonisolated struct BackupArchive: Hashable, Identifiable, Sendable {
    let url: URL
    let name: String
    let manifest: BackupManifest

    var id: URL {
        url
    }

    var createdAt: Date {
        manifest.createdAt
    }

    var byteCount: Int {
        manifest.byteCount
    }
}

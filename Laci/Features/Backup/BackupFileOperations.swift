import Foundation

/// The file system calls the backup makes, as closures so a test can make one of them fail at a
/// chosen step. Sizes come from `.fileSizeKey`; creation and modification dates are never read
/// (required-reason API, SPEC §15), the manifest carries the timestamp instead.
nonisolated struct BackupFileOperations: Sendable {
    var fileExists: @Sendable (URL) -> Bool
    var createDirectory: @Sendable (URL) throws -> Void
    var copyItem: @Sendable (URL, URL) throws -> Void
    var moveItem: @Sendable (URL, URL) throws -> Void
    var removeItem: @Sendable (URL) throws -> Void
    var contentsOfDirectory: @Sendable (URL) throws -> [URL]
    var write: @Sendable (Data, URL) throws -> Void
    var read: @Sendable (URL) throws -> Data
    var fileSize: @Sendable (URL) throws -> Int
    /// True for a local file; for an iCloud item, whether its bytes are on this device.
    var isDownloaded: @Sendable (URL) throws -> Bool

    static let live = BackupFileOperations(
        fileExists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) },
        createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
        copyItem: { try FileManager.default.copyItem(at: $0, to: $1) },
        moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
        removeItem: { try FileManager.default.removeItem(at: $0) },
        contentsOfDirectory: {
            try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
        },
        write: { try $0.write(to: $1, options: .atomic) },
        read: { try Data(contentsOf: $0) },
        fileSize: { try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 },
        isDownloaded: { url in
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard values.isUbiquitousItem == true else { return true }
            return values.ubiquitousItemDownloadingStatus == .current
        }
    )
}

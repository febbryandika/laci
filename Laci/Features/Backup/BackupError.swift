import Foundation

nonisolated enum BackupError: Error, Hashable, Sendable {
    /// No iCloud Documents container: not signed in, iCloud Drive off, or the entitlement missing.
    case iCloudUnavailable
    case copyFailed(String)
    /// The archive was written; only the removal of older ones failed.
    case pruneFailed(String)
    case manifestUnreadable(String)
    /// A backup written by a build with a different schema; opening it could migrate or corrupt.
    case incompatibleSchema(found: String)
    /// The archive is in iCloud but not yet on this device.
    case notDownloaded
    case restoreFailed(String)
}

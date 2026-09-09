// LaciCore — SwiftData models, repositories and CSV codecs (SPEC §4). Schema V1 and the
// repositories arrive in Phase 2; nothing here imports SwiftData yet.

import Foundation

/// Package marker: lets the smoke test prove the module builds and links under Swift 6
/// strict concurrency before any real type exists.
public enum LaciCorePackage {
    public static let name = "LaciCore"
}

import Foundation
@testable import Laci
import Testing

@MainActor
@Suite("Store file protection")
struct StoreFileProtectionTests {
    private static func protection(of url: URL) throws -> URLFileProtection? {
        var url = url
        url.removeAllCachedResourceValues()
        return try url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
    }

    /// The folder gets the class too, but a folder reports none back on the simulator, so only the
    /// files are checked.
    @Test("The store and its journal files carry the SPEC §15 class")
    func storeFilesAreProtected() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "laci-protection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appending(path: "Laci.store")
        let container = try Store.container(at: storeURL)
        withExtendedLifetime(container) {}
        #expect(try Self.protection(of: storeURL) == .completeUntilFirstUserAuthentication)
        for suffix in ["-wal", "-shm"] {
            let url = folder.appending(path: "Laci.store\(suffix)")
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                #expect(try Self.protection(of: url) == .completeUntilFirstUserAuthentication, "\(suffix)")
            }
        }
    }

    @Test("A file moved in by a restore is brought back to the class when the store reopens")
    func reopenReappliesTheClass() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "laci-protection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appending(path: "Laci.store")
        _ = try Store.container(at: storeURL)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.none], ofItemAtPath: storeURL.path(percentEncoded: false)
        )
        _ = try Store.container(at: storeURL)
        #expect(try Self.protection(of: storeURL) == .completeUntilFirstUserAuthentication)
    }
}

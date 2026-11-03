import Foundation
@testable import Laci
import Testing

/// SPEC §15: the manifest matches §5.4 row for row, checked against the table written out here
/// rather than against the manifest's own idea of itself. A manifest that overstates is a rejection,
/// one that understates is a lie. SPEC.md is not in the repository, so the rows are restated.
@MainActor
@Suite("Privacy manifest")
struct PrivacyManifestTests {
    /// §5.4 row by row: the data types each one adds to the manifest. Only Crashlytics sends data
    /// anyone but the shop can read.
    static let boundaryTable: [(row: String, collected: Set<String>)] = [
        ("Apple · StoreKit", []),
        ("Apple · iCloud Documents", []),
        (
            "Google · Crashlytics",
            ["NSPrivacyCollectedDataTypeCrashData", "NSPrivacyCollectedDataTypeOtherDiagnosticData"]
        ),
        ("Bluetooth printer", []),
        ("A file the user picked", []),
        ("A recipient the user picked", []),
    ]

    private static func manifest() throws -> [String: Any] {
        // Bundle.main is the host app: this proves the file reached the bundle root, where iOS reads it.
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test("No tracking and no tracking domains")
    func noTracking() throws {
        let manifest = try Self.manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        let domains = try #require(manifest["NSPrivacyTrackingDomains"] as? [String])
        #expect(domains.isEmpty)
    }

    @Test("Collected data is exactly the §5.4 table: nothing more, nothing less")
    func collectedMatchesTheTable() throws {
        let entries = try #require(try Self.manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let declared = entries.compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        #expect(declared.count == Set(declared).count)
        #expect(Set(declared) == Self.boundaryTable.reduce(into: Set<String>()) { $0.formUnion($1.collected) })
    }

    @Test("Crash data is not linked to anyone, not tracking, and only for keeping the app working")
    func collectedIsUnlinked() throws {
        let entries = try #require(try Self.manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        #expect(!entries.isEmpty)
        for entry in entries {
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == false)
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
            let purposes = entry["NSPrivacyCollectedDataTypePurposes"] as? [String]
            #expect(purposes == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        }
    }

    @Test("Required-reason APIs: UserDefaults with CA92.1 and no other category")
    func requiredReasons() throws {
        let entries = try #require(try Self.manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(entry["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    @Test("Camera, Bluetooth and Face ID say why in Indonesian, in the built Info.plist", arguments: [
        ("NSCameraUsageDescription", "memindai barcode"),
        ("NSBluetoothAlwaysUsageDescription", "mencetak struk"),
        ("NSFaceIDUsageDescription", "layar khusus pemilik"),
    ])
    func usageStrings(key: String, reason: String) throws {
        // `infoDictionary`, not `object(forInfoDictionaryKey:)`: that one answers in the test
        // host's language, and the Indonesian source string is what is being checked.
        let value = try #require(Bundle.main.infoDictionary?[key] as? String)
        #expect(value.contains(reason))
    }
}

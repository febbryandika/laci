import Foundation

/// What the UI tests ask of a launch (SPEC §11): an in-memory store seeded with the real catalogue,
/// or left empty, and every network-shaped read reporting unavailable so the airplane-mode run has
/// something to prove. DEBUG-only, like `TrialPolicy.overrideKey`: Release never reads these keys.
nonisolated struct LaunchEnvironment: Hashable, Sendable {
    static let uiTestingKey = "LACI_UI_TESTING"
    static let emptyKey = "LACI_UI_EMPTY"
    static let offlineKey = "LACI_OFFLINE"
    static let consentKey = "LACI_UI_CONSENT"
    static let lockKey = "LACI_UI_LOCK"

    /// An in-memory store instead of the on-disk one, with the settings wiped first.
    let isUITesting: Bool
    /// The warung-200 fixture, loaded before the first screen; off with `emptyKey`.
    let loadsFixture: Bool
    /// The iCloud container is missing and the App Store price cannot be loaded.
    let isOffline: Bool
    /// A UI test that wants the crash-reporting consent screen; every other UI test skips it.
    let asksConsent: Bool
    /// A UI test that wants the owner PIN, held in memory; every other UI test walks through.
    let enforcesLock: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG
            isUITesting = environment[Self.uiTestingKey] == "1"
            loadsFixture = isUITesting && environment[Self.emptyKey] != "1"
            isOffline = environment[Self.offlineKey] == "1"
            asksConsent = environment[Self.consentKey] == "1"
            enforcesLock = environment[Self.lockKey] == "1"
        #else
            isUITesting = false
            loadsFixture = false
            isOffline = false
            asksConsent = false
            enforcesLock = false
        #endif
    }

    static let current = LaunchEnvironment()
}

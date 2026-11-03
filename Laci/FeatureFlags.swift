/// Feature flags are compile-time constants (SPEC §1 deviations): there is no Remote Config, so a
/// flag is decided by what the build contains, and a test can supply its own conformance.
nonisolated protocol FeatureFlags {
    /// Crashlytics is linked into this build, so the consent screen and the toggle exist.
    static var crashReporting: Bool { get }
}

nonisolated enum BuildFlags: FeatureFlags {
    #if canImport(FirebaseCrashlytics)
        static let crashReporting = true
    #else
        static let crashReporting = false
    #endif
}

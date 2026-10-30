import Foundation
#if canImport(FirebaseCrashlytics)
    import FirebaseCore
    import FirebaseCrashlytics
#endif

/// Crash reporting is two verbs and nothing else (SPEC §5.4: crash stack, device model, OS and app
/// version, never sale data). There is deliberately no way to log a message, record an error, or
/// set a key or a user id through it, so no code path can hand Crashlytics a sale, a product name
/// or an amount. `scripts/assert-crash-reporting.sh` keeps it that way.
@MainActor
protocol CrashReporting: AnyObject {
    func start()
    func stop()
}

/// The build without Crashlytics linked: nothing to start.
final class NoCrashReporter: CrashReporting {
    func start() {}
    func stop() {}
}

#if canImport(FirebaseCrashlytics)
    /// Firebase is configured here and nowhere else, and only after the shop said yes: until then
    /// Crashlytics is not installed in the process at all.
    final class FirebaseCrashReporter: CrashReporting {
        func start() {
            guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
                Log.store.error("crash reporting not started: GoogleService-Info.plist missing")
                return
            }
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
            Log.store.notice("crash reporting started")
        }

        /// Revoking: collection off and unsent reports deleted now. Firebase cannot be unconfigured
        /// inside a running process; from the next launch it is never configured.
        func stop() {
            guard FirebaseApp.app() != nil else { return }
            let crashlytics = Crashlytics.crashlytics()
            crashlytics.setCrashlyticsCollectionEnabled(false)
            crashlytics.deleteUnsentReports()
            Log.store.notice("crash reporting stopped")
        }
    }
#endif

/// The shop's answer to the consent screen. `nil` until asked.
nonisolated enum CrashReportingDecision: String, Hashable, Sendable {
    case granted
    case declined
}

nonisolated enum CrashReportingSettings {
    private static let key = "diagnostics.crashReporting"

    static func decision(in defaults: UserDefaults = .standard) -> CrashReportingDecision? {
        defaults.string(forKey: key).flatMap(CrashReportingDecision.init(rawValue:))
    }

    static func save(_ decision: CrashReportingDecision, in defaults: UserDefaults = .standard) {
        defaults.set(decision.rawValue, forKey: key)
    }
}

/// The consent and the reporter it controls. On `AppSession`, because a restore must not forget it.
@MainActor
@Observable
final class CrashConsent {
    private(set) var decision: CrashReportingDecision?
    let isAvailable: Bool
    private let reporter: any CrashReporting
    private let defaults: UserDefaults

    init(
        reporter: any CrashReporting = CrashConsent.buildReporter(), flags: any FeatureFlags.Type = BuildFlags.self,
        defaults: UserDefaults = .standard
    ) {
        self.reporter = reporter
        self.defaults = defaults
        isAvailable = flags.crashReporting
        decision = CrashReportingSettings.decision(in: defaults)
    }

    static func buildReporter() -> any CrashReporting {
        #if canImport(FirebaseCrashlytics)
            FirebaseCrashReporter()
        #else
            NoCrashReporter()
        #endif
    }

    /// Launch: the reporter starts only on a yes given earlier. Undecided starts nothing.
    func startIfConsented() {
        guard isAvailable, decision == .granted else { return }
        reporter.start()
    }

    func grant() {
        guard isAvailable else { return }
        decision = .granted
        CrashReportingSettings.save(.granted, in: defaults)
        reporter.start()
    }

    /// Both "Jangan kirim" on the consent screen and switching the toggle off.
    func decline() {
        let wasGranted = decision == .granted
        decision = .declined
        CrashReportingSettings.save(.declined, in: defaults)
        if wasGranted {
            reporter.stop()
        }
    }

    /// The consent screen is asked once, at the first launch of a build that can report, and
    /// never over a UI test unless the test asked for it.
    func shouldAsk(launch: LaunchEnvironment) -> Bool {
        isAvailable && decision == nil && (!launch.isUITesting || launch.asksConsent)
    }
}

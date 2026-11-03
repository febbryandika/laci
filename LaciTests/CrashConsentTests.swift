import Foundation
@testable import Laci
import Testing

/// Records what the consent asked of the reporter; nothing here touches Firebase.
@MainActor
final class SpyCrashReporter: CrashReporting {
    private(set) var starts = 0
    private(set) var stops = 0

    func start() {
        starts += 1
    }

    func stop() {
        stops += 1
    }
}

enum CrashReportingLinked: FeatureFlags {
    static let crashReporting = true
}

enum CrashReportingAbsent: FeatureFlags {
    static let crashReporting = false
}

@MainActor
@Suite("Crash-reporting consent")
struct CrashConsentTests {
    let defaults: UserDefaults
    let reporter = SpyCrashReporter()

    init() throws {
        let suite = "CrashConsentTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func consent(_ flags: any FeatureFlags.Type = CrashReportingLinked.self) -> CrashConsent {
        CrashConsent(reporter: reporter, flags: flags, defaults: defaults)
    }

    @Test("Undecided starts nothing at launch")
    func undecided() {
        let consent = consent()
        consent.startIfConsented()
        #expect(consent.decision == nil)
        #expect(reporter.starts == 0)
    }

    @Test("Declined starts nothing at launch")
    func declinedAtLaunch() {
        CrashReportingSettings.save(.declined, in: defaults)
        consent().startIfConsented()
        #expect(reporter.starts == 0)
    }

    @Test("A yes given earlier starts the reporter at launch")
    func grantedAtLaunch() {
        CrashReportingSettings.save(.granted, in: defaults)
        consent().startIfConsented()
        #expect(reporter.starts == 1)
    }

    @Test("Granting starts the reporter and is remembered")
    func grant() {
        let consent = consent()
        consent.grant()
        #expect(reporter.starts == 1)
        #expect(CrashReportingSettings.decision(in: defaults) == .granted)
    }

    @Test("Revoking stops the reporter and is remembered, so the next launch starts nothing")
    func revoke() {
        let consent = consent()
        consent.grant()
        consent.decline()
        #expect(reporter.stops == 1)
        #expect(CrashReportingSettings.decision(in: defaults) == .declined)
        let relaunched = self.consent()
        relaunched.startIfConsented()
        #expect(reporter.starts == 1)
    }

    @Test("Declining on the consent screen has nothing to stop")
    func declineFirst() {
        consent().decline()
        #expect(reporter.stops == 0)
        #expect(reporter.starts == 0)
    }

    @Test("A build without Crashlytics never starts it, whatever was stored")
    func absent() {
        CrashReportingSettings.save(.granted, in: defaults)
        let consent = consent(CrashReportingAbsent.self)
        consent.startIfConsented()
        consent.grant()
        #expect(reporter.starts == 0)
        #expect(!consent.shouldAsk(launch: LaunchEnvironment(environment: [:])))
    }

    @Test("The question is asked once, at a normal launch")
    func asksOnce() {
        let consent = consent()
        #expect(consent.shouldAsk(launch: LaunchEnvironment(environment: [:])))
        consent.decline()
        #expect(!consent.shouldAsk(launch: LaunchEnvironment(environment: [:])))
    }

    @Test("A UI test is not interrupted by the question unless it asks for it")
    func uiTests() {
        let consent = consent()
        let plain = LaunchEnvironment(environment: [LaunchEnvironment.uiTestingKey: "1"])
        let asking = LaunchEnvironment(environment: [
            LaunchEnvironment.uiTestingKey: "1", LaunchEnvironment.consentKey: "1",
        ])
        #if DEBUG
            #expect(!consent.shouldAsk(launch: plain))
            #expect(consent.shouldAsk(launch: asking))
        #endif
    }
}

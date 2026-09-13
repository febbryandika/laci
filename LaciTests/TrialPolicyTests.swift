import Foundation
@testable import Laci
import Testing

@Suite("Trial policy")
struct TrialPolicyTests {
    @Test("The limit is thirty without an override")
    func defaultLimit() {
        #expect(TrialPolicy.saleLimit(environment: [:]) == 30)
    }

    @Test("A DEBUG environment override replaces the limit", arguments: [("2", 2), ("0", 0)])
    func debugOverride(raw: String, expected: Int) {
        let limit = TrialPolicy.saleLimit(environment: [TrialPolicy.overrideKey: raw])
        #if DEBUG
            #expect(limit == expected)
        #else
            #expect(limit == 30)
        #endif
    }

    @Test("A malformed override is ignored", arguments: ["", "abc", "-1", "2.5"])
    func malformedOverride(raw: String) {
        #expect(TrialPolicy.saleLimit(environment: [TrialPolicy.overrideKey: raw]) == 30)
    }
}

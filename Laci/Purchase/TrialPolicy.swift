import Foundation

/// SPEC §3.4: everything works for 30 sales. The override is DEBUG-only so a walkthrough can reach
/// the paywall without ringing thirty sales; Release compiles it out.
nonisolated enum TrialPolicy {
    static let defaultSaleLimit = 30
    static let overrideKey = "LACI_TRIAL_SALE_LIMIT"

    static func saleLimit(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        #if DEBUG
            if let raw = environment[overrideKey], let limit = Int(raw), limit >= 0 {
                return limit
            }
        #endif
        return defaultSaleLimit
    }
}

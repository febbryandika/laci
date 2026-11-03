import os

/// The one subsystem and the five categories of SPEC §14. Money, product names, SKUs and barcode
/// values are logged `.private`; counts, sale numbers, MTU, durations and error cases `.public`.
/// The app reading its own store gets `.private` values back in clear, so "Bagikan log" rebuilds
/// each message from its parts and writes `<private>` for them (`LogStoreReader.message`). Events a
/// support question needs are `.notice` or above; per-chunk noise is `.debug`.
nonisolated enum Log {
    /// Not the bundle identifier (`id.Laci`): the log export filters on this string.
    static let subsystem = "id.laci"

    static let sale = Logger(subsystem: subsystem, category: "sale")
    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let printing = Logger(subsystem: subsystem, category: "print")
    static let closeout = Logger(subsystem: subsystem, category: "closeout")
    static let store = Logger(subsystem: subsystem, category: "store")

    /// SPEC §10's two budgets, as intervals Instruments shows under Points of Interest.
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}

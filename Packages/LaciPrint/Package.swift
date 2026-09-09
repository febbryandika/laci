// swift-tools-version: 6.0
import PackageDescription

/// Language mode 6 already implies complete strict concurrency; the experimental flag is
/// kept as an explicit, greppable statement of intent.
let strictSwift: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "LaciPrint",
    platforms: [.iOS("26.5"), .macOS("26.0")],
    products: [.library(name: "LaciPrint", targets: ["LaciPrint"])],
    targets: [
        .target(name: "LaciPrint", swiftSettings: strictSwift),
        .testTarget(name: "LaciPrintTests", dependencies: ["LaciPrint"], swiftSettings: strictSwift),
    ]
)

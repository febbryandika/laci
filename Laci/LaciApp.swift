import LaciCore
import LaciMoney
import LaciPrint
import SwiftUI

/// Composition root. Every dependency the app needs is built here, once, and handed down.
/// Empty until repositories, the printer transport and the scanner arrive in later phases.
struct Dependencies {}

@main
struct LaciApp: App {
    private let dependencies = Dependencies()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}

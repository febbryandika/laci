import Foundation

/// The one question the sell screen asks (SPEC §3.4). `UnlockStore` answers it from StoreKit; the
/// tests answer it with a fake, so a checkout test never touches the App Store.
@MainActor
protocol UnlockGating: AnyObject, Observable {
    var isUnlocked: Bool { get }
}

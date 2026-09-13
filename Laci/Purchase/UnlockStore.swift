import Foundation
import Observation
import os
import StoreKit

enum UnlockError: Error {
    case unverified
}

/// SPEC §5.1: the on-device entitlement for the one non-consumable. No server receipt validation,
/// because there is no server data to gate; the entitlement gates a code path on the same device
/// that holds the transaction. Owned by `AppSession`, not `Dependencies`, so a restore never tears
/// down the listener.
@Observable
@MainActor
final class UnlockStore: UnlockGating {
    static let productID = "id.laci.unlock"

    private(set) var isUnlocked = false
    /// Loaded when the paywall appears, never at launch: the price is the only network-shaped read.
    private(set) var product: StoreKit.Product?
    private(set) var productLoadFailed = false
    // Not tracked: a task handle is not UI state, and only a stored (not computed) Sendable
    // property may be read from the nonisolated deinit below.
    @ObservationIgnored private var updates: Task<Void, Never>?
    private let log = Logger(subsystem: "id.laci", category: "purchase")

    func start() {
        guard updates == nil else { return }
        // Family sharing, refunds and revocations arrive here and nowhere else, so this listener
        // starts at launch and is never torn down. Detached: StoreKit's stream is iterated off the
        // main actor and only the state write hops there.
        updates = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case let .verified(transaction) = result else { continue }
                await transaction.finish()
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.productID == Self.productID, transaction.revocationDate == nil else { continue }
            isUnlocked = true
            return
        }
        isUnlocked = false // .unverified lands here: locked, with a restore button, not an error
    }

    func purchase(_ product: StoreKit.Product) async throws {
        guard case let .success(result) = try await product.purchase() else { return }
        guard case let .verified(transaction) = result else { throw UnlockError.unverified }
        await transaction.finish()
        await refresh()
    }

    func loadProduct() async {
        do {
            product = try await StoreKit.Product.products(for: [Self.productID]).first
            productLoadFailed = product == nil
        } catch {
            log.error("product load failed: \(String(describing: error), privacy: .public)")
            productLoadFailed = true
        }
    }

    /// SPEC §5.4: the one sanctioned round trip besides purchase. Failure leaves the shop locked
    /// with the button still there; it is never a failure of the app.
    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }

    deinit { updates?.cancel() }
}

import Foundation
@testable import Laci
import LaciCore
import Testing

@MainActor
@Suite("App session for a UI-test launch")
struct AppSessionLaunchTests {
    @Test("The seeded launch holds the warung-200 catalogue")
    func seeded() throws {
        let session = AppSession.uiTesting(LaunchEnvironment(environment: [LaunchEnvironment.uiTestingKey: "1"]))
        let products = try session.dependencies.products.all(includeArchived: false)
        #expect(products.count >= 190)
        #expect(session.backups.storeURL != Store.storeURL)
    }

    @Test("The empty launch holds no products")
    func empty() throws {
        let session = AppSession.uiTesting(LaunchEnvironment(environment: [
            LaunchEnvironment.uiTestingKey: "1", LaunchEnvironment.emptyKey: "1",
        ]))
        let products = try session.dependencies.products.all(includeArchived: false)
        #expect(products.isEmpty)
    }

    @Test("Offline: the backup container is missing and the price cannot be loaded")
    func offline() async {
        let session = AppSession.uiTesting(LaunchEnvironment(environment: [
            LaunchEnvironment.uiTestingKey: "1", LaunchEnvironment.offlineKey: "1",
        ]))
        let backedUp = await session.backups.backupNow()
        #expect(!backedUp)
        #expect(session.backups.status == .failed(.iCloudUnavailable))
        await session.unlock.loadProduct()
        #expect(session.unlock.productLoadFailed)
        #expect(session.unlock.product == nil)
    }

    @Test("Online: the scratch backup folder is a local fallback")
    func online() async {
        let session = AppSession.uiTesting(LaunchEnvironment(environment: [LaunchEnvironment.uiTestingKey: "1"]))
        await session.backups.refreshArchives()
        #expect(session.backups.location?.isLocalFallback == true)
    }
}

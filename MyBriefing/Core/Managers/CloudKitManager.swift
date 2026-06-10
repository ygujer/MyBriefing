import Foundation
import CloudKit
import Combine

/// Central authority for iCloud availability and the user's sync preference.
///
/// **Before CloudKit writes will work**, enable the iCloud capability in
/// Xcode ▸ Signing & Capabilities (add iCloud, tick CloudKit, and let Xcode
/// create the default container). That will update MyBriefing.entitlements
/// with the correct `icloud-services` and `icloud-container-identifiers` keys.
///
/// All CloudKit consumers must check `canSync` before performing any network
/// operation. When `canSync` is false every operation is silently skipped —
/// the app always falls back to local UserDefaults storage.
@MainActor
final class CloudKitManager: ObservableObject {

    // MARK: - Published state

    /// User-facing toggle stored in UserDefaults.
    @Published var isSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(isSyncEnabled, forKey: Self.syncEnabledKey) }
    }

    /// Current iCloud account status; refreshed on `start()` and on demand.
    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine

    // MARK: - Computed

    /// True when the user opted in AND iCloud is signed-in and available.
    var canSync: Bool { isSyncEnabled && accountStatus == .available }

    // MARK: - CloudKit references

    let container: CKContainer
    var privateDatabase: CKDatabase { container.privateCloudDatabase }

    // MARK: - Init

    private static let syncEnabledKey = "iCloudSyncEnabled"

    init() {
        isSyncEnabled = UserDefaults.standard.bool(forKey: Self.syncEnabledKey)
        container = CKContainer.default()
    }

    // MARK: - Lifecycle

    /// Call once at app launch. Checks account status without blocking the UI.
    func start() async {
        await refreshAccountStatus()
    }

    /// Re-checks iCloud account status. Safe to call at any time.
    func refreshAccountStatus() async {
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            accountStatus = .couldNotDetermine
        }
    }
}

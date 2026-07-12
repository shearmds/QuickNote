import Foundation
import SwiftUI
import Combine
import CloudKit

/// Observable iCloud-sync status for the note store. This exists because the
/// container silently falls back to a local-only store when CloudKit can't be
/// brought up — which looks exactly like "sync is broken." Surfacing the real
/// state (menu-bar item + an in-app banner) means a non-syncing build tells you
/// so instead of pretending everything is fine.
@MainActor
final class SyncStatus: ObservableObject {
    static let shared = SyncStatus()

    enum State {
        case checking      // still determining
        case syncing       // CloudKit up + iCloud account available
        case localOnly     // fell back to a local store (no CloudKit)
        case noAccount     // CloudKit configured but no iCloud account signed in
    }

    @Published private(set) var state: State = .checking

    private let containerID = "iCloud.com.shearair.QuickNote"

    private init() {
        refresh()
        NotificationCenter.default.addObserver(
            self, selector: #selector(accountChanged),
            name: .CKAccountChanged, object: nil
        )
    }

    /// True unless we're actively and healthily syncing — drives whether the
    /// warning banner shows.
    var needsAttention: Bool { state == .localOnly || state == .noAccount }

    var label: String {
        switch state {
        case .checking:  return "Checking iCloud…"
        case .syncing:   return "Syncing via iCloud"
        case .localOnly: return "iCloud unavailable — notes are on this device only"
        case .noAccount: return "Not signed in to iCloud — notes are on this device only"
        }
    }

    var symbol: String {
        switch state {
        case .checking:  return "icloud"
        case .syncing:   return "checkmark.icloud"
        case .localOnly, .noAccount: return "exclamationmark.icloud"
        }
    }

    @objc private func accountChanged() { refresh() }

    func refresh() {
        // Force the container to initialize so `usesCloudKit` is set, then read it.
        _ = AppModelContainer.shared
        guard AppModelContainer.usesCloudKit else {
            state = .localOnly
            return
        }
        state = .checking
        CKContainer(identifier: containerID).accountStatus { [weak self] status, _ in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .available:
                    self.state = .syncing
                case .noAccount:
                    self.state = .noAccount
                default:
                    // restricted / couldNotDetermine / temporarilyUnavailable
                    self.state = .localOnly
                }
            }
        }
    }
}

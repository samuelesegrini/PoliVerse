import Foundation

/// Where the last ``WatchSnapshot`` is kept between launches and between
/// processes.
///
/// On the Watch two processes read it: the app, and the widget extension that
/// draws the complications and the Smart Stack cards. They meet in the Watch's
/// own copy of the app group — the same identifier as the phone's, but a
/// separate container, because an app group never crosses devices. On the
/// phone it only remembers what was last sent.
nonisolated enum WatchSnapshotStore {
    /// The defaults both Watch processes can reach, falling back to the
    /// process's own when the group is not provisioned — a simulator build
    /// without signing, for one.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: OfflineStore.groupIdentifier) ?? .standard
    }

    /// The last snapshot kept, if any this build can read.
    static func load() -> WatchSnapshot? {
        guard let data = defaults.data(forKey: WatchSnapshot.cacheName) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    /// Keeps a snapshot, replacing the previous one.
    ///
    /// - Parameter snapshot: The snapshot to keep.
    static func save(_ snapshot: WatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WatchSnapshot.cacheName)
    }
}

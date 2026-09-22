import Foundation
import WidgetKit

/// Tells the widgets their data changed — once per kind, and only after the file is
/// on disk.
///
/// Requests gather for ``window`` and then go out as one reload per kind, behind
/// ``OfflineStore``'s pending writes, so a widget never reloads onto the file it is
/// replacing. WidgetKit throttles frequent reloads from a foreground app and
/// recommends a final reload as the app leaves the screen, which
/// ``appDidEnterBackground()`` performs.
///
/// See `docs/metrickit-performance.md` §3.7.
@MainActor
enum WidgetReloader {
    /// Kinds waiting to be reloaded by the next flush.
    private static var pending: Set<WidgetKind> = []
    /// Every kind that changed since the app came forward, reloaded once more as it
    /// leaves the screen.
    private static var changedWhileActive: Set<WidgetKind> = []
    /// The gathering window currently running, if any.
    private static var debounce: Task<Void, Never>?

    /// How long requests gather before going out.
    static let window: Duration = .seconds(2)

    /// Asks for these kinds to be reloaded, opening a gathering window if none is
    /// running.
    ///
    /// - Parameter kinds: The widget kinds whose data changed.
    static func request(_ kinds: Set<WidgetKind>) {
        pending.formUnion(kinds)
        changedWhileActive.formUnion(kinds)
        guard debounce == nil else { return }
        debounce = Task {
            try? await Task.sleep(for: window)
            await flush()
        }
    }

    /// Sends whatever has gathered, after waiting for pending offline writes.
    ///
    /// A background refresh must call this before reporting completion: once iOS suspends
    /// the app, the gathering window never ends.
    static func flush() async {
        debounce?.cancel()
        debounce = nil
        let kinds = pending
        pending = []
        guard !kinds.isEmpty else { return }
        await OfflineStore.shared.flushed()
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        }
        DiagnosticsLog.shared.widgetsReloaded()
    }

    /// Reloads everything that changed while the app was on screen.
    ///
    /// The final reload WidgetKit recommends as an app leaves the foreground.
    static func appDidEnterBackground() async {
        pending.formUnion(changedWhileActive)
        changedWhileActive = []
        await flush()
    }
}

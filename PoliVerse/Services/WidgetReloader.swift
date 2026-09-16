import Foundation
import WidgetKit

/// Tells widgets their data changed — once, for the kinds that read it, after
/// the file is on disk.
///
/// Three services each called `reloadAllTimelines()` straight after saving,
/// so one foreground revalidation reloaded every widget up to three times,
/// sometimes before the write it announced had happened. WidgetKit throttles
/// frequent reloads from a foreground app, and suggests a final reload as the
/// app leaves the screen instead (`docs/metrickit-performance.md` §3.7).
///
/// So: requests gather for a moment and go out as one reload per kind, after
/// `OfflineStore`'s pending writes; and whatever changed while the app was
/// open is reloaded once more when it goes to the background.
@MainActor
enum WidgetReloader {
    private static var pending: Set<WidgetKind> = []
    private static var changedWhileActive: Set<WidgetKind> = []
    private static var debounce: Task<Void, Never>?

    /// How long requests gather before going out.
    static let window: Duration = .seconds(2)

    static func request(_ kinds: Set<WidgetKind>) {
        pending.formUnion(kinds)
        changedWhileActive.formUnion(kinds)
        guard debounce == nil else { return }
        debounce = Task {
            try? await Task.sleep(for: window)
            await flush()
        }
    }

    /// Sends whatever is gathered now. A background refresh must call this
    /// before it finishes: once iOS suspends the app, the gathering window
    /// never ends.
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

    /// The final reload WidgetKit recommends as the app leaves the screen.
    static func appDidEnterBackground() async {
        pending.formUnion(changedWhileActive)
        changedWhileActive = []
        await flush()
    }
}

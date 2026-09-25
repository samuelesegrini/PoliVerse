import SwiftUI

/// PoliVerse on the wrist: what is on now, the next few days, the sittings
/// ahead and the career.
///
/// Everything it shows comes from the phone through ``WatchBridge``. There is
/// no sign-in here and no networking: a Watch has neither the session nor the
/// Keychain, and a second copy of the login would be a second place for
/// credentials to live.
@main
struct PoliVerseWatchApp: App {
    /// The link to the phone.
    @State private var bridge = WatchBridge.shared

    /// The app's scene.
    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(bridge)
        }
        // The system wakes the app in the background when the phone sends a
        // snapshot for the complications. The session has to be up to take
        // it, and the task has to last until it has been taken, or the app
        // is suspended with the payload still on its way in.
        .backgroundTask(.watchConnectivity) {
            await WatchBridge.shared.start()
            for _ in 0..<40 {
                guard await WatchBridge.shared.hasContentPending else { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Brings the session up as soon as the app exists, so a context waiting
    /// from before this launch is delivered.
    init() {
        WatchBridge.shared.start()
    }
}

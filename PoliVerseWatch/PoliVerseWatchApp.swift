import SwiftUI

/// PoliVerse on the wrist: today's lectures and the next exam.
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
            WatchTodayView()
                .environment(bridge)
        }
    }

    /// Brings the session up as soon as the app exists, so a context waiting
    /// from before this launch is delivered.
    init() {
        WatchBridge.shared.start()
    }
}

import Foundation
import Observation
import OSLog
import UIKit

/// Carries the URL CieID hands back to whichever login web view is on screen.
///
/// The return arrives at the app level (`onOpenURL`), but it has to be loaded
/// into the *specific* `WKWebView` that started the flow — that view holds the
/// session cookies the IdP set. This is the wire between the two.
@Observable
final class CieIDRouter {
    /// Set when CieID returns; the active login view consumes it.
    private(set) var pendingURL: URL?
    /// Set when CieID reports a failure instead.
    private(set) var errorMessage: String?
    /// True while the user is over in the CieID app.
    private(set) var isAwaitingCieID = false

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "cieid")

    /// Called from `onOpenURL`. Returns true if this URL was ours.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        // Logged at info so it survives in the device log: if CieID ever
        // changes the shape it returns, this line is what identifies it.
        // Path only — the query can carry conversation identifiers.
        log.info("Incoming URL scheme=\(url.scheme ?? "nil", privacy: .public) prefix=\(url.absoluteString.prefix(60), privacy: .public)")

        guard let recovered = CieIDBridge.returnURL(from: url) else {
            log.error("Incoming URL was not a recognised CieID return")
            return false
        }
        log.info("Recovered return host=\(recovered.host ?? "nil", privacy: .public) path=\(recovered.path, privacy: .public)")

        isAwaitingCieID = false

        if let message = CieIDBridge.errorMessage(in: recovered) {
            log.error("CieID returned an error: \(message)")
            errorMessage = message
            return true
        }

        log.debug("CieID returned; resuming the web session")
        pendingURL = recovered
        return true
    }

    /// The login view calls this once it has loaded the URL.
    func consume() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }

    func clearError() { errorMessage = nil }

    /// Hands an IdP navigation to the CieID app with `sourceApp` attached, so
    /// it comes back here instead of opening the default browser.
    ///
    /// - Returns: false when CieID is not installed, so the caller can offer
    ///   the App Store instead of silently doing nothing.
    @MainActor
    func openCieID(for url: URL) async -> Bool {
        guard let handoff = CieIDBridge.handoffURL(for: url) else {
            log.error("Could not build the CieID hand-off URL")
            return false
        }
        log.info("Handing off to CieID for path=\(url.path, privacy: .public)")
        isAwaitingCieID = true
        let opened = await UIApplication.shared.open(handoff)
        if !opened {
            isAwaitingCieID = false
            log.error("CieID app did not accept the URL — probably not installed")
        }
        return opened
    }

    @MainActor
    func openAppStore() {
        UIApplication.shared.open(CieIDBridge.appStoreURL)
    }
}

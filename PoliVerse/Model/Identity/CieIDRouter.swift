import Foundation
import Observation
import OSLog
import UIKit

/// Carries the URL the CieID app hands back to whichever sign-in web view started
/// the flow.
///
/// The return arrives at app level through `onOpenURL`, but it has to be loaded
/// into the specific `WKWebView` that began the flow, since that view holds the
/// cookies the identity provider set. This type is the wire between the two:
/// ``handle(_:)`` receives the return and ``consume()`` hands it to the view.
///
/// ``openCieID(for:)`` makes the outbound leg, and ``openAppStore()`` covers the
/// case where CieID is not installed.
@Observable
final class CieIDRouter {
    /// The return URL waiting to be loaded, consumed by the active sign-in view.
    private(set) var pendingURL: URL?
    /// What CieID reported instead of a return, or `nil`. Cleared by ``clearError()``.
    private(set) var errorMessage: String?
    /// `true` while the student is over in the CieID app.
    private(set) var isAwaitingCieID = false

    /// Diagnostic log for this type, under the `cieid` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "cieid")

    /// Receives an incoming URL from `onOpenURL`.
    ///
    /// A recognised return either sets ``errorMessage``, when CieID reported a failure,
    /// or ``pendingURL``, for the sign-in view to load. Either way it clears
    /// ``isAwaitingCieID``.
    ///
    /// - Parameter url: The incoming URL.
    /// - Returns: `true` when the URL was a CieID return and has been handled, `false`
    ///   when it belongs to something else.
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

    /// Takes the pending return URL, clearing it.
    ///
    /// - Returns: The URL to load, or `nil` when there is none.
    func consume() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }

    /// Discards the reported error, once it has been shown.
    func clearError() { errorMessage = nil }

    /// Hands an identity-provider navigation to the CieID app, with `sourceApp`
    /// attached so that it returns here rather than opening the default browser.
    ///
    /// - Parameter url: The navigation CieID should take over.
    /// - Returns: `false` when the hand-off URL cannot be built or CieID is not
    ///   installed, so the caller can offer the App Store instead of doing nothing.
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

    /// Opens CieID's App Store page.
    @MainActor
    func openAppStore() {
        UIApplication.shared.open(CieIDBridge.appStoreURL)
    }
}

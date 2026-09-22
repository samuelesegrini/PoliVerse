import SwiftUI

/// The WeBeep (Moodle) login.
///
/// Two hand-offs happen here: the CIE detour, handled inside ``AuthWebView``,
/// and our own switch from the logged-in page to Moodle's token endpoint.
struct WeBeepLoginWebView: View {
    /// Carries a CIE sign-in's return back into this web view.
    let router: CieIDRouter
    /// Called with the token once the handshake completes.
    let onToken: (WeBeepAuth.MoodleToken) -> Void
    /// Called when the handshake fails.
    let onError: (any Error) -> Void
    /// Called when CIE was chosen and the CieID app is not installed, so the caller can offer
    /// the App Store.
    var onCieIDMissing: () -> Void = {}

    /// Fresh per attempt, so the payload signature is bound to this login.
    @State private var passport = WeBeepAuth.newPassport()
    @State private var handedOffToLaunch = false

    /// The view's content.
    var body: some View {
        AuthWebView(
            startURL: WeBeepAuth.loginURL,
            router: router,
            decide: { url in
                if let scheme = url.scheme, WeBeepAuth.acceptedSchemes.contains(scheme) {
                    return .finish {
                        do {
                            onToken(try WeBeepAuth.token(from: url, passport: passport))
                        } catch {
                            onError(error)
                        }
                    }
                }

                if !handedOffToLaunch, isLoggedInPage(url) {
                    handedOffToLaunch = true
                    return .load(WeBeepAuth.launchURL(passport: passport))
                }

                return .allow
            },
            onError: onError,
            onCieIDMissing: onCieIDMissing
        )
    }

    /// Moodle lands on `/my/` or `/my/index.php`, sometimes with a query.
    private func isLoggedInPage(_ url: URL) -> Bool {
        guard url.host == "webeep.polimi.it" else { return false }
        return ["/my/", "/my", "/my/index.php"].contains(url.path)
    }
}

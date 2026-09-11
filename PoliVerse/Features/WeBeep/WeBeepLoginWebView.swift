import SwiftUI

/// The WeBeep (Moodle) login.
///
/// Two hand-offs happen here: the CIE detour, handled inside ``AuthWebView``,
/// and our own switch from the logged-in page to Moodle's token endpoint.
struct WeBeepLoginWebView: View {
    let router: CieIDRouter
    let onToken: (WeBeepAuth.MoodleToken) -> Void
    let onError: (any Error) -> Void
    var onCieIDMissing: () -> Void = {}

    /// Fresh per attempt, so the payload signature is bound to this login.
    @State private var passport = WeBeepAuth.newPassport()
    @State private var handedOffToLaunch = false

    var body: some View {
        AuthWebView(
            startURL: WeBeepAuth.loginURL,
            router: router,
            decide: { url in
                if let scheme = url.scheme, WeBeepAuth.acceptedSchemes.contains(scheme) {
                    do {
                        onToken(try WeBeepAuth.token(from: url, passport: passport))
                    } catch {
                        onError(error)
                    }
                    return .finish
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

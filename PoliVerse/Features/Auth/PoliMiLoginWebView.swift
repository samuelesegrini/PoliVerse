import SwiftUI
import OSLog

/// The PoliMi OAuth login.
///
/// Runs in two phases. The first ends the **SSO session** at `aunicalogin`,
/// the second authorizes.
///
/// The logout step is not politeness. While an `aunicalogin` session is live,
/// the IdP can answer a new authorize request by re-issuing a code against the
/// grant that session already carries — ignoring the wider `scope` we ask for.
/// The result is a user who logs in again and gets the *same* narrow token
/// back, and services that keep answering "Scope OAuth non valido … Code: 33".
/// Ending the SSO session first is what forces a genuinely new grant.
struct PoliMiLoginWebView: View {
    /// Fetched from `/jaf/oauth/params`; determines which scopes the resulting
    /// token actually carries.
    let oauthParams: ServiceDirectory.OAuthParams
    let router: CieIDRouter
    /// Resolves the `aunicalogin` logout URL. Nil skips straight to authorize.
    let logoutURL: URL?
    let onCode: (String) -> Void
    let onError: (any Error) -> Void
    var onCieIDMissing: () -> Void = {}

    private enum Phase: Equatable { case endingSession, authorizing }

    @State private var phase: Phase
    @State private var state = UUID().uuidString

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "oauth")

    init(
        oauthParams: ServiceDirectory.OAuthParams,
        router: CieIDRouter,
        logoutURL: URL?,
        onCode: @escaping (String) -> Void,
        onError: @escaping (any Error) -> Void,
        onCieIDMissing: @escaping () -> Void = {}
    ) {
        self.oauthParams = oauthParams
        self.router = router
        self.logoutURL = logoutURL
        self.onCode = onCode
        self.onError = onError
        self.onCieIDMissing = onCieIDMissing
        _phase = State(initialValue: logoutURL == nil ? .authorizing : .endingSession)
    }

    private var authorizeURL: URL {
        PoliMiOAuth.authorizationURL(params: oauthParams, state: state)
    }

    var body: some View {
        AuthWebView(
            startURL: phase == .endingSession ? (logoutURL ?? authorizeURL) : authorizeURL,
            router: router,
            decide: { url in
                if let code = PoliMiOAuth.authCode(from: url) {
                    onCode(code)
                    return .finish
                }
                return .allow
            },
            onError: onError,
            onCieIDMissing: onCieIDMissing,
            onFinished: { finishedURL in
                guard phase == .endingSession else { return }
                // The logout page has rendered; the SSO cookie is gone. Move on.
                if isLogoutComplete(finishedURL) {
                    logAuthorize()
                    phase = .authorizing
                }
            }
        )
        // A new identity when the phase flips forces the web view to be rebuilt
        // with the new start URL.
        .id(phase)
        .onAppear {
            if phase == .authorizing { logAuthorize() }
        }
    }

    /// Any page settling on `aunicalogin` after the logout request counts —
    /// the logout renders a confirmation page rather than redirecting.
    private func isLogoutComplete(_ url: URL?) -> Bool {
        guard let host = url?.host else { return true }
        return host.contains("polimi.it")
    }

    /// Logs what is actually being requested.
    ///
    /// The scope list is the whole question when the services answer
    /// "Scope OAuth non valido", and the only way to tell a fetched list from a
    /// stale constant is to print the URL that really gets opened.
    private func logAuthorize() {
        let scopes = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "scope" }?.value ?? ""
        log.notice("""
            Authorizing — client=\(oauthParams.clientId, privacy: .public) \
            scopeCount=\(scopes.split(separator: " ").count, privacy: .public) \
            hasAgenda=\(scopes.contains("agenda"), privacy: .public) \
            hasReactIae=\(scopes.contains("react_iae"), privacy: .public) \
            hasPianoStudente=\(scopes.contains("pianostudente"), privacy: .public)
            """)
        log.debug("Authorize URL: \(authorizeURL.absoluteString, privacy: .public)")
    }
}

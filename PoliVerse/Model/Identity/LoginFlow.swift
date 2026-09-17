import Foundation
import Observation
import OSLog

/// How the student got in: the login, the logout, the restore at launch, and
/// the career re-login.
///
/// Split from ``Session``, which is *who* the student is. The two were one
/// object of 387 lines named by 49 files, so every screen that wanted a
/// matricola also depended on the OAuth machinery. This half is the one
/// almost nothing needs: thirteen call sites against the other's hundred and
/// forty.
///
/// Reached as `session.login` rather than injected on its own. That is
/// deliberate and temporary: it keeps the construction order and the sequence
/// of the login exactly as they were — the one path in the app that no test
/// can exercise, because it needs a real Politecnico account. Injecting it
/// separately, and so actually lowering ``Session``'s fan-in, is a one-line
/// change per view to make once a compiler can confirm it.
@Observable
final class LoginFlow {
    /// Unowned because ``Session`` owns this, and an object cannot keep its
    /// owner alive.
    private unowned let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "login")

    init(session: Session) {
        self.session = session
    }

    /// Decides the opening screen: a stored token means we can go straight in.
    func restore() async {
        // Learn where the services live before calling any of them.
        await session.directory.load()

        if session.useMockData {
            await session.signIn(MockData.student)
            return
        }
        guard await session.tokens.hasToken else {
            session.enter(.signedOut)
            return
        }

        // A token only carries the scopes it was granted at creation; refreshing
        // never widens them. If the Politecnico has added a scope since this
        // token was minted, it will 401 on the new service indefinitely, so
        // re-authenticate rather than leave the user on a half-broken session.
        //
        // A nil recorded scope counts as a mismatch, not as "fine": every token
        // minted before the app started recording it is precisely the token
        // that predates the scope change, so `if let` would skip exactly the
        // case this check exists for.
        let currentScope = session.directory.oauth.scope
        let granted = await session.tokens.grantedScope
        if granted != currentScope {
            log.notice("Stored token scope differs from current (had scope: \(granted != nil, privacy: .public)); re-authenticating")
            await session.tokens.clear()
            session.enter(.signedOut)
            return
        }
        do {
            let dto = try await session.api.send(
                APIRequest(host: .app, path: "/jaf/internal/user"),
                as: PoliMiUserDTO.self
            )
            await session.signIn(dto.toStudent())
            await session.loadProfile()
        } catch {
            log.error("Restore failed: \(error.localizedDescription)")
            session.enter(.signedOut)
        }
    }

    /// Prepares for a genuinely fresh login.
    ///
    /// Does two things the user cannot do from inside the app:
    ///
    /// 1. Deletes any stored token. A token's scopes are fixed at creation and
    ///    refreshing never widens them, so carrying one across a scope change
    ///    keeps the old grant alive forever.
    /// 2. Resolves the `aunicalogin` logout URL, so the login can end the SSO
    ///    session before authorizing. With that session live the IdP may
    ///    re-issue a code against the existing grant and ignore the wider scope
    ///    we ask for — which is how "log in again" can return the same narrow
    ///    token.
    ///
    /// - Returns: the logout URL, or nil to authorize directly.
    func prepareForLogin() async -> URL? {
        await session.directory.load()
        await session.tokens.clear()

        do {
            let link = try await session.api.send(
                PoliMiOAuth.logoutLinkRequest(serviceID: session.directory.oauth.serviceID),
                as: PoliMiOAuth.LogoutLink.self
            )
            guard let target = link.targetURL, let url = URL(string: target) else {
                log.notice("No SSO logout URL returned; authorizing directly")
                return nil
            }
            log.info("Ending SSO session before authorizing")
            return url
        } catch {
            // Not fatal: without it the login may reuse the old grant, but it
            // is still better to try than to block the user entirely.
            log.error("Could not resolve the SSO logout URL: \(error.localizedDescription)")
            return nil
        }
    }

    /// Adopts a credential minted by the official web app.
    ///
    /// No code exchange: the app already did it, and the token it produced is
    /// one the data services accept — which the one we minted ourselves was
    /// not. See ``PoliMiAppLoginWebView`` for what was ruled out first.
    func completeLogin(token: PoliMiToken) async {
        session.enter(.exchangingCode)
        await session.directory.load()
        await session.tokens.set(token)
        await session.tokens.setGrantedScope(session.directory.oauth.scope)

        do {
            let dto = try await session.api.send(
                APIRequest(host: .app, path: "/jaf/internal/user"),
                as: PoliMiUserDTO.self
            )
            await session.signIn(dto.toStudent())
            session.serviceAuthorizationFailed = false
            await session.loadProfile()
        } catch {
            log.error("Could not read the user after login: \(error.localizedDescription)")
            session.enter(.failed(error.localizedDescription))
        }
    }

    /// The enrolment the next login should land on.
    ///
    /// Persisted, because the login it applies to happens after the app has
    /// signed out and the in-memory session.state is gone. Cleared once used.
    var pendingMatricola: String? {
        get { UserDefaults.standard.string(forKey: "pendingMatricola") }
        set { UserDefaults.standard.set(newValue, forKey: "pendingMatricola") }
    }

    /// Signs out so the user can sign back in on another enrolment.
    ///
    /// The Politecnico's own `/careerChange` errors for this account — in the
    /// official app too — so the working route is a full re-login. The lever
    /// that actually decides which enrolment the new token binds to is the
    /// favourite, set through `PUT /v1/careers/favorite/{matricola}` while
    /// the current token still works; the matricola on the authorize request
    /// is only a hint on top of that.
    func beginCareerRelogin(matricola: String) async {
        pendingMatricola = matricola
        log.notice("Signing out to re-authenticate on matricola \(matricola, privacy: .public)")
        await signOut()
    }

    /// Adopts a token minted for a different enrolment.
    ///
    /// Deliberately not ``completeLogin(token:)``: that moves the session.state to
    /// `.exchangingCode`, which drops the whole UI back to the login screen.
    /// A career change is not a login — the person stays signed in, and only
    /// the matricola their grant is bound to moves. If reading the user back
    /// fails, the previous career is still signed in and working, so the old
    /// session.state is kept rather than replaced with an error screen.
    func adopt(_ token: PoliMiToken) async {
        await session.tokens.set(token)
        await session.tokens.setGrantedScope(session.directory.oauth.scope)
        do {
            let dto = try await session.api.send(
                APIRequest(host: .app, path: "/jaf/internal/user"),
                as: PoliMiUserDTO.self
            )
            await session.signIn(dto.toStudent())
            session.serviceAuthorizationFailed = false
            await session.loadProfile()
            log.notice("Now on matricola \(dto.matricola, privacy: .public)")
        } catch {
            log.error("Career switch could not read the user: \(error.localizedDescription)")
        }
    }

    /// Exchanges the authcode from the web flow for a token pair.
    func completeLogin(authCode: String) async {
        session.enter(.exchangingCode)
        // The login web view may have been opened before the session.directory landed.
        await session.directory.load()
        do {
            let token = try await session.api.send(
                PoliMiOAuth.tokenExchangeRequest(authCode: authCode),
                as: PoliMiToken.self
            )
            await session.tokens.set(token)
            await session.tokens.setGrantedScope(session.directory.oauth.scope)

            let dto = try await session.api.send(
                APIRequest(host: .app, path: "/jaf/internal/user"),
                as: PoliMiUserDTO.self
            )
            await session.signIn(dto.toStudent())
            session.serviceAuthorizationFailed = false
            await session.loadProfile()
        } catch {
            log.error("Code exchange failed: \(error.localizedDescription)")
            session.enter(.failed(error.localizedDescription))
        }
    }

    func signOut() async {
        session.serviceAuthorizationFailed = false
        // Server-side invalidation, as the official app does. Best effort: the
        // local token is dropped either way.
        if await session.tokens.hasToken {
            _ = try? await session.api.send(PoliMiOAuth.revokeRequest)
        }
        await session.tokens.clear()
        // Otherwise the next person to sign in on this device finds the
        // previous session.student's courses in Spotlight.
        SpotlightIndex().clear()
        // Same reason: reminders naming someone else's lectures would keep
        // arriving after they signed out.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        // Cookies only: the login page's 13.7 MB of JavaScript and CSS stays
        // cached, so signing back in is fast. Nothing identifying remains.
        await LoginWebKit.endSession()
        // The offline copies are this session.student's record. Someone else signing
        // in on the same device must not find them.
        if let matricola = session.student?.matricola {
            OfflineStore.shared.clear(account: matricola)
        }
        if session.useMockData {
            await session.signIn(MockData.student)
        } else {
            session.enter(.signedOut)
            await session.profileBox.set(matricola: nil)
            // A widget must show "sign in", not "no lectures".
            SharedAccount.update(matricola: nil, firstName: nil)
        }
    }}

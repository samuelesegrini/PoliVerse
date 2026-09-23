import Foundation
import Observation
import OSLog
import UserNotifications

/// How the student gets in and out: the restore at launch, the sign-in, the
/// sign-out, and the re-sign-in that moves to another enrolment.
///
/// Split from ``Session``, which holds who the student is. This is the half almost
/// nothing needs, and it is the only thing besides ``Session`` itself permitted to
/// move a session between states, through ``Session/enter(_:)``.
///
/// Reached as `session.login` rather than injected separately, which keeps the
/// construction order and the sequence of the sign-in fixed.
@Observable
final class LoginFlow {
    /// The session this flow drives. Unowned, because ``Session`` owns this.
    private unowned let session: Session
    /// Diagnostic log for this type, under the `login` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "login")

    /// Creates the flow.
    ///
    /// - Parameter session: The session to drive. Held unowned.
    init(session: Session) {
        self.session = session
    }

    /// Decides the opening screen from what is already on the device.
    ///
    /// Sample data signs in as ``Student/sample``. With no stored token the session
    /// goes straight to ``Session/State/signedOut``. With one, the service directory is
    /// loaded, the token's granted scope is compared against the current scope list,
    /// and the student is read back from `/jaf/internal/user`.
    ///
    /// A scope mismatch clears the token and returns to sign-in: a token carries the
    /// scopes granted at creation and refreshing never widens them, so a token minted
    /// before a scope existed would keep failing on that one service indefinitely. A
    /// token with no recorded scope counts as a mismatch, since those are precisely the
    /// tokens that predate the change.
    ///
    /// The directory is loaded only on the path that needs it. The two paths that call
    /// nothing — a fresh install and sample data — warm it in the background instead,
    /// so the first frame is not held behind two network round trips.
    func restore() async {
        if session.useMockData {
            warmDirectory()
            await session.signIn(Student.sample)
            return
        }
        guard await session.tokens.hasToken else {
            // Straight to the welcome — then fetch, with the screen already up.
            session.enter(.signedOut)
            warmDirectory()
            return
        }

        // Restoring a real session does need it: the scope comparison below
        // reads the current scopes, and the request after it needs the host.
        await session.directory.load()

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

    /// Loads the service directory without holding the caller up.
    ///
    /// Unstructured, because the caller has just put a screen on screen. Safe to run
    /// alongside a path that loads the directory itself, since
    /// ``ServiceDirectory/load()`` returns immediately once loaded.
    private func warmDirectory() {
        Task { await session.directory.load() }
    }

    /// Prepares for a genuinely fresh sign-in.
    ///
    /// Clears any stored token, since a token's scopes are fixed at creation and
    /// carrying one across a scope change keeps the old grant alive, then resolves the
    /// `aunicalogin` logout URL so that the single sign-on session can be ended before
    /// authorising. With that session live the identity provider may re-issue a code
    /// against the existing grant and ignore the wider scope being asked for.
    ///
    /// - Returns: The logout URL to visit first, or `nil` to authorise directly. A
    ///   failure to resolve it returns `nil` rather than blocking the sign-in.
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

    /// Adopts a token minted by the Politecnico's own web app and signs the student in.
    ///
    /// No code exchange is involved: the web app has already performed it. See
    /// ``PoliMiAppLoginWebView``.
    ///
    /// Records the current scope on the token, reads the student back and clears
    /// ``Session/serviceAuthorizationFailed``. A failure to read the student enters
    /// ``Session/State/failed(_:)``.
    ///
    /// - Parameter token: The pair the web app produced.
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

    /// The enrolment the next sign-in should land on, or `nil` for none.
    ///
    /// Persisted in `UserDefaults`, because the sign-in it applies to happens after the
    /// app has signed out and in-memory state is gone. Cleared once used.
    var pendingMatricola: String? {
        get { UserDefaults.standard.string(forKey: "pendingMatricola") }
        set { UserDefaults.standard.set(newValue, forKey: "pendingMatricola") }
    }

    /// Records the target enrolment and signs out, so the student can sign back in on
    /// it.
    ///
    /// A full re-sign-in rather than the identity provider's `/careerChange`, which
    /// errors for at least some accounts. What decides the enrolment the new token
    /// binds to is the favourite career set while the current token still works; the
    /// matricola on the authorisation request is only a hint on top of that.
    ///
    /// - Parameter matricola: The enrolment to land on.
    func beginCareerRelogin(matricola: String) async {
        pendingMatricola = matricola
        log.notice("Signing out to re-authenticate on matricola \(matricola, privacy: .public)")
        await signOut()
    }

    /// Adopts a token minted for a different enrolment, without leaving the signed-in
    /// state.
    ///
    /// Deliberately not ``completeLogin(token:)``, which enters
    /// ``Session/State/exchangingCode`` and so drops the interface back to the sign-in
    /// screen. A career change is not a sign-in: the person stays signed in and only
    /// the enrolment their grant is bound to moves.
    ///
    /// If the student cannot be read back, the previous state is kept, since the
    /// previous career is still signed in and working.
    ///
    /// - Parameter token: The pair minted for the other enrolment.
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

    /// Exchanges an authorisation code for a token pair and signs the student in.
    ///
    /// Loads the service directory first, since the sign-in web view may have opened
    /// before it landed. A failure at either step enters ``Session/State/failed(_:)``.
    ///
    /// - Parameter authCode: The code from ``PoliMiOAuth/authCode(from:)``.
    func completeLogin(authCode: String) async {
        session.enter(.exchangingCode)
        // The login web view may have been opened before the directory landed.
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

    /// Signs the student out and removes everything of theirs from the device.
    ///
    /// Invalidates the token server-side on a best-effort basis, clears the stored
    /// pair, empties the Spotlight index, cancels every pending reminder, removes the
    /// sign-in cookies while keeping the page cache, deletes this account's offline
    /// records, and clears ``SharedAccount`` so a widget shows an invitation to sign in
    /// rather than an empty day.
    ///
    /// Under ``Session/useMockData`` it signs back in as ``Student/sample`` instead of
    /// reaching ``Session/State/signedOut``.
    func signOut() async {
        session.serviceAuthorizationFailed = false
        // Server-side invalidation, as the official app does. Best effort: the
        // local token is dropped either way.
        if await session.tokens.hasToken {
            _ = try? await session.api.send(PoliMiOAuth.revokeRequest)
        }
        await session.tokens.clear()
        // Otherwise the next person to sign in on this device finds the
        // previous student's courses in Spotlight.
        SpotlightIndex().clear()
        // Same reason: reminders naming someone else's lectures would keep
        // arriving after they signed out.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        // Cookies only: the login page's 13.7 MB of JavaScript and CSS stays
        // cached, so signing back in is fast. Nothing identifying remains.
        await LoginWebKit.endSession()
        // The recordings keep a web session of their own; it goes with the
        // student, like everything else.
        await RecordingsWebKit.endSession()
        // Saved lectures too: someone else signing in must not find them.
        RecordingDownloads.shared.deleteAll()
        // The offline copies are this student's record. Someone else signing
        // in on the same device must not find them.
        if let matricola = session.student?.matricola {
            OfflineStore.shared.clear(account: matricola)
        }
        if session.useMockData {
            await session.signIn(Student.sample)
        } else {
            session.enter(.signedOut)
            await session.profileBox.set(matricola: nil)
            // A widget must show "sign in", not "no lectures".
            SharedAccount.update(matricola: nil, firstName: nil)
        }
    }}

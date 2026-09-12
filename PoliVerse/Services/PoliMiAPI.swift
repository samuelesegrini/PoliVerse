import Foundation
import OSLog

/// Which backend a request goes to.
///
/// Resolved through ``ServiceDirectory`` rather than hardcoded, because the
/// Politecnico moves these. `www22.dmz.polimi.it/iae` became
/// `api.polimi.it/iae`, and the app that hardcoded the old host simply broke.
typealias APIHost = ServiceDirectory.Service

nonisolated struct APIRequest {
    var host: APIHost
    var path: String
    var method: String = "GET"
    var query: [URLQueryItem] = []
    var body: Data?
    var authenticated: Bool = true

    /// Appends `matricola` when the service's configured profile is non-zero.
    ///
    /// The official client applies this rule to every call:
    ///
    /// ```js
    /// profile === 0 ? client.get(path) : client.get(path, {params: {matricola}})
    /// ```
    ///
    /// `props` reports `iae.profile` and `libretto.profile` as `0`, so those
    /// need nothing — but `ws_aule.profile` is `3`, and a rooms call without
    /// `matricola` would simply not work. Encoding the rule once means adding
    /// a service does not mean rediscovering it.
    var sendsMatricola: Bool = false
    /// Overrides `poliAuthProfile` for this one call.
    ///
    /// Exists for `ws_aule`, whose configured profile (3) is a profile the
    /// signed-in account may not hold — a student has profile 1 — and the
    /// service answers "Utente non abilitato" rather than saying so.
    var profileOverride: Int?
}

nonisolated enum APIError: LocalizedError {
    case badStatus(Int, body: String)
    /// The path returned 404 — the service moved or was withdrawn, which is a
    /// different problem from the network being down and deserves saying so.
    case endpointGone(String)
    /// The request was cancelled — almost always because the view that asked
    /// for it went away. Not a failure, and must never reach the user: it was
    /// surfacing as "Impossibile raggiungere i server del Politecnico" every
    /// time someone left a tab while it was loading.
    case cancelled
    /// The account is not permitted to use this service, whatever the token
    /// says. Permanent for this user, so retrying or re-authenticating is
    /// pointless — the UI should say so rather than offer a login.
    case notEntitled(String, body: String)
    /// The token is valid but was not minted for this service.
    ///
    /// The backends report it as 401 with
    /// "Scope OAuth non valido. Effettuare logout/login…  Code: 33", which no
    /// amount of refreshing fixes — the scopes are fixed when the token is
    /// created. Only a fresh login helps.
    case invalidScope
    case transport(any Error)
    case decoding(any Error)
    case retriesExhausted(Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, _): String(localized: "Il server ha risposto \(code).")
        case .endpointGone: String(localized: "Questo servizio del Politecnico non è più disponibile a questo indirizzo.")
        case .cancelled: String(localized: "Richiesta annullata.")
        case .notEntitled: String(localized: "Il Politecnico non abilita il tuo profilo a questo servizio.")
        case .invalidScope: String(localized: "L'accesso è scaduto. Accedi di nuovo per continuare.")
        case .transport: String(localized: "Impossibile raggiungere i server del Politecnico.")
        case .decoding: String(localized: "Risposta del server non leggibile.")
        case .retriesExhausted(let n): String(localized: "Nessuna risposta dopo \(n) tentativi.")
        }
    }

    /// True when retrying or waiting will not help — the endpoint itself is the
    /// problem.
    var isPermanent: Bool {
        switch self {
        case .endpointGone, .invalidScope, .notEntitled, .cancelled: true
        case .transport(let error): (error as NSError).code == NSURLErrorCannotFindHost
        default: false
        }
    }
}

/// Thin async client over `URLSession`.
///
/// Two deliberate differences from PoliFemo's axios setup:
///
/// 1. **Bounded backoff.** Their `RETRY_INDEFINETELY` default re-issued a failed
///    request every 3 s forever, so a permanently-500 endpoint pinned the
///    network and the battery. Here retries cap out and the delay grows.
/// 2. **One refresh.** A 401 asks ``TokenStore`` for a token; the actor
///    collapses concurrent requests into a single refresh.
/// The text to show the user for an error, or nil when there is nothing to
/// say.
///
/// Cancellation returns nil: a request abandoned because its view went away is
/// not a failure, and reporting it put "Impossibile raggiungere i server del
/// Politecnico" on screen for anyone who left a tab mid-load.
nonisolated func userFacingMessage(_ error: any Error) -> String? {
    if let apiError = error as? APIError, case .cancelled = apiError { return nil }
    if PoliMiAPI.isCancellation(error) { return nil }
    return error.localizedDescription
}

nonisolated final class PoliMiAPI: Sendable {
    private let session: URLSession
    private let tokens: TokenStore
    private let directory: ServiceDirectory
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "api")

    private let maxRetries = 3

    /// Supplies the value of the `poliAuthProfile` header.
    ///
    /// Injected rather than fixed because the correct value is the signed-in
    /// user's profile, which is only known after login.
    private let profileID: @Sendable () async -> Int

    /// Supplies `matricola` for the services that require it as a query
    /// parameter. Injected for the same reason as ``profileID``: it is only
    /// known once the user has signed in.
    private let matricola: @Sendable () async -> String?

    /// Called when the server says the token's scopes are wrong, so the app can
    /// drop it and send the user back to login rather than retrying forever.
    private let onInvalidScope: @Sendable () async -> Void

    init(
        tokens: TokenStore,
        directory: ServiceDirectory,
        profileID: @escaping @Sendable () async -> Int = { PoliMiProfile.student },
        matricola: @escaping @Sendable () async -> String? = { nil },
        onInvalidScope: @escaping @Sendable () async -> Void = {},
        session: URLSession = .shared
    ) {
        self.tokens = tokens
        self.directory = directory
        self.profileID = profileID
        self.matricola = matricola
        self.onInvalidScope = onInvalidScope
        self.session = session
    }

    /// Recognises the backends' "wrong scopes" 401.
    ///
    /// Matched on the message because the status code and `statusCode` field
    /// are the same 401 used for an ordinary expired token, and the two need
    /// opposite responses: refresh for one, re-login for the other.
    static func isInvalidScope(_ body: String) -> Bool {
        guard !isNotEntitled(body) else { return false }
        return body.localizedCaseInsensitiveContains("Scope OAuth non valido")
            || body.localizedCaseInsensitiveContains("JafUnauthorizedException")
    }

    /// "This account may not use this service", as distinct from "this token
    /// is no good".
    ///
    /// Both arrive as 401 `JafUnauthorizedException`, so the generic check
    /// above claimed the session had expired and sent the user back to login —
    /// where nothing would change, because signing in again grants the same
    /// account the same services. `ws_aule` is the case that exposed it: its
    /// configured profile is 3, and a student holds profile 1.
    static func isNotEntitled(_ body: String) -> Bool {
        if body.localizedCaseInsensitiveContains("Utente non abilitato") { return true }
        // Anchored: a plain `contains("Code: 6")` also matches `Code: 60` and
        // `Code: 66`, which would read a genuine session failure as a
        // permissions one and never offer the login that would fix it.
        return body.range(of: "Code:\\s*6(?![0-9])", options: .regularExpression) != nil
    }

    func send<T: Decodable>(_ request: APIRequest, as type: T.Type) async throws -> T {
        let data = try await send(request)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            // Log a slice of the body: when an endpoint moves, the shape often
            // moves with it, and guessing from the decoding error alone is
            // hopeless.
            let preview = String(data: data.prefix(1200), encoding: .utf8) ?? "<binary>"
            log.error("Decoding \(String(describing: T.self)) failed: \(error)")
            log.error("Body was: \(preview, privacy: .public)")
            throw APIError.decoding(error)
        }
    }

    @discardableResult
    func send(_ request: APIRequest) async throws -> Data {
        var attempt = 0
        var didRetryAuth = false

        while true {
            let urlRequest = try await makeURLRequest(request)

            do {
                let (data, response) = try await session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else { return data }

                switch http.statusCode {
                case 200..<300:
                    return data

                case 401 where request.authenticated && !didRetryAuth:
                    // Token rejected despite looking valid locally. Refresh once
                    // and replay; a second 401 means the session is genuinely gone.
                    didRetryAuth = true
                    _ = try await tokens.forceRefresh()
                    continue

                // Applies to every host, including the ones the app depends
                // on. `iae` really does answer "Utente non abilitato Code: 6"
                // for this account, and a fresh login returns the same answer
                // — so routing it to re-authentication would be a loop, and
                // reporting it as a bare 401 hides what the server actually
                // said. It is never retried and never re-authenticates.
                case 401 where Self.isNotEntitled(String(data: data, encoding: .utf8) ?? ""):
                    let denied = String(data: data, encoding: .utf8) ?? ""
                    log.error("Service not permitted for this account — path=\(request.path, privacy: .public)")
                    // Deliberately no `onInvalidScope`: the token is fine and
                    // logging in again would grant exactly the same access.
                    throw APIError.notEntitled(request.path, body: String(denied.prefix(200)))

                case 401 where Self.isInvalidScope(String(data: data, encoding: .utf8) ?? ""):
                    let body = String(data: data, encoding: .utf8) ?? ""
                    log.error("""
                        Token rejected for scope — path=\(request.path, privacy: .public) \
                        body=\(String(body.prefix(200)), privacy: .public)
                        """)
                    // Only for services the app depends on. A service that
                    // is refused by design must not flag the whole session as
                    // unauthenticated — everything else is working.
                    if request.host.refusalMeansBrokenSession {
                        await onInvalidScope()
                        throw APIError.invalidScope
                    }
                    throw APIError.notEntitled(request.path, body: String(body.prefix(200)))

                case 401:
                    // A 401 that survived a refresh is not a stale token — it is
                    // the service refusing this token for this resource, usually
                    // a missing scope. The body says which, so log it: from the
                    // outside "expired session" and "token has no authority
                    // here" look identical.
                    let body = String(data: data, encoding: .utf8) ?? ""
                    log.error("""
                        401 after refresh — host=\(request.host.rawValue, privacy: .public) \
                        path=\(request.path, privacy: .public) \
                        authHeader=\(urlRequest.value(forHTTPHeaderField: "Authorization") != nil, privacy: .public) \
                        body=\(String(body.prefix(300)), privacy: .public)
                        """)
                    throw APIError.badStatus(401, body: String(body.prefix(300)))

                case 500..<600:
                    attempt += 1
                    guard attempt <= maxRetries else {
                        throw APIError.retriesExhausted(maxRetries)
                    }
                    // 0.5s, 1s, 2s — bounded, unlike PoliFemo's infinite 3s loop.
                    let delay = UInt64(0.5 * pow(2, Double(attempt - 1)) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                    continue

                case 404:
                    log.error("Endpoint gone: \(request.path, privacy: .public)")
                    throw APIError.endpointGone(request.path)

                default:
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw APIError.badStatus(http.statusCode, body: String(body.prefix(300)))
                }
            } catch let error as APIError {
                throw error
            } catch let error as AuthError {
                throw error
            } catch {
                // Cancellation first: it is not a failure, and retrying a
                // cancelled task is doubly pointless — the caller has gone.
                if Self.isCancellation(error) { throw APIError.cancelled }

                // Retrying a permanent failure just burns battery and delays
                // the error the user needs to see. A host that does not resolve
                // will not resolve on the fourth attempt either.
                guard Self.isRetryable(error) else {
                    log.error("Not retrying \((error as NSError).code): \(error.localizedDescription)")
                    throw APIError.transport(error)
                }
                attempt += 1
                guard attempt <= maxRetries else { throw APIError.transport(error) }
                try await Task.sleep(nanoseconds: UInt64(0.5 * pow(2, Double(attempt - 1)) * 1_000_000_000))
            }
        }
    }

    /// Exposed for tests; the classification is what stopped a six-deep retry
    /// storm against a host that no longer resolves.
    static func isRetryableForTesting(_ error: any Error) -> Bool { isRetryable(error) }

    /// Which of the official app's two HTTP clients serves this request.
    ///
    /// The `jaf` layer and the `iae`/`libretto` services go through axios; the
    /// `/v1/*` app endpoints and the agenda go through openapi-fetch. They
    /// differ only in how they treat `poliAuthD_profile`.
    static func usesAxiosClient(_ request: APIRequest) -> Bool {
        switch request.host {
        case .iae, .libretto, .wsAule: true
        case .app: request.path.hasPrefix("/jaf/")
        case .agenda, .weBeep: false
        }
    }

    /// Whether a transport failure is worth another attempt.
    ///
    /// DNS and TLS failures are verdicts, not hiccups. Treating them as
    /// transient produced six round trips per request against a host that no
    /// longer exists.
    /// Whether this error is the task being cancelled rather than anything
    /// going wrong. Cancellation arrives in two shapes — Swift's own
    /// `CancellationError` and `URLError` -999 — and both mean the caller
    /// stopped caring, not that the Politecnico is unreachable.
    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static func isRetryable(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch nsError.code {
        case NSURLErrorTimedOut,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorResourceUnavailable:
            return true
        case NSURLErrorCannotFindHost,          // -1003, NXDOMAIN
             NSURLErrorBadURL,
             NSURLErrorUnsupportedURL,
             NSURLErrorNotConnectedToInternet,  // retrying offline is pointless
             NSURLErrorCancelled,
             NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return false
        default:
            return false
        }
    }

    private func makeURLRequest(_ request: APIRequest) async throws -> URLRequest {
        let base = await MainActor.run { directory.baseURL(for: request.host) }
        var components = URLComponents(
            url: base.appendingPathComponent(request.path),
            resolvingAgainstBaseURL: false
        )!
        var query = request.query
        // The rule the official client applies to every call:
        //
        //   profile === 0 ? client.get(path) : client.get(path, {params: {matricola}})
        //
        // `iae` and `libretto` report profile 0 and so need nothing, which is
        // why this went unnoticed until `ws_aule` — profile 3 — became the
        // first service where omitting it makes the call wrong.
        if request.sendsMatricola, let value = await matricola() {
            query.append(URLQueryItem(name: "matricola", value: value))
        }
        if !query.isEmpty { components.queryItems = query }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if request.authenticated {
            let token = try await tokens.validToken()
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            // The official app's request middleware sends this alongside the
            // bearer token:
            //
            //   n.headers.set("Authorization", `Bearer ${t}`)
            //   a && n.headers.set("poliAuthProfile", `${a.profile}`)
            //
            // Both profile headers, exactly as the official interceptor sets
            // them:
            //
            //   if (headers[PROFILE_PARAM]   === undefined) headers[PROFILE_PARAM]   = profile?.profile  ?? 0
            //   if (headers[D_PROFILE_PARAM] === undefined) headers[D_PROFILE_PARAM] = profile?.dprofile ?? "JAF_D_PROFILE_VUOTO"
            //
            // Two things that are easy to get wrong and were:
            //
            // `poliAuthD_profile` is *always* sent. When the account has no
            // secondary profile — ours reports `dprofile: null` — it carries
            // the literal `JAF_D_PROFILE_VUOTO`, not nothing.
            //
            // `poliAuthProfile` is not always the user's. For `iae` and
            // `libretto` the official client is built as
            // `Qr({baseURL, profile: Number(props["iae.profile"])})`, which
            // presets the header to the *service's* profile (`0`); the user's
            // profile is only the fallback for clients that set none.
            let user = await profileID()
            let serviceProfile = await MainActor.run {
                directory.profile(for: request.host, userProfile: user)
            }
            let profile = request.profileOverride ?? serviceProfile
            urlRequest.setValue(String(profile), forHTTPHeaderField: "poliAuthProfile")

            // The two official clients disagree about this header, so match
            // whichever one serves the path.
            //
            //   axios (`Qr`/`uxe`, the /jaf/* and iae/libretto calls):
            //     headers[D_PROFILE] = dprofile ?? "JAF_D_PROFILE_VUOTO"   // always
            //
            //   openapi-fetch (`Fhe`, the /v1/* and agenda calls):
            //     a.dprofile && headers.set(D_PROFILE, a.dprofile)         // only if present
            //
            // An account with no secondary profile therefore gets the sentinel
            // on one client and no header at all on the other.
            let dProfile = await MainActor.run { directory.dProfile }
            if let dProfile {
                urlRequest.setValue(dProfile, forHTTPHeaderField: "poliAuthD_profile")
            } else if Self.usesAxiosClient(request) {
                urlRequest.setValue(PoliMiProfile.emptyDProfile,
                                    forHTTPHeaderField: "poliAuthD_profile")
            }
        }
        urlRequest.timeoutInterval = 30
        return urlRequest
    }
}

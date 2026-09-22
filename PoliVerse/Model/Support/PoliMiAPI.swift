import Foundation
import OSLog

/// Which backend a request goes to.
///
/// Resolved through ``ServiceDirectory`` rather than hardcoded, since the
/// Politecnico moves these hosts.
typealias APIHost = ServiceDirectory.Service

/// One request to one Politecnico backend, before a base URL, headers or a token
/// are attached.
///
/// ``PoliMiAPI`` resolves and sends it; ``PublicHTTP`` sends the unauthenticated
/// ones; ``FixtureHTTP`` matches it by ``path``.
nonisolated struct APIRequest {
    /// Which backend to address.
    var host: APIHost
    /// The path below the host's base URL, leading slash included.
    var path: String
    /// The HTTP method.
    var method: String = "GET"
    /// Query items to send. ``sendsMatricola`` may append one more.
    var query: [URLQueryItem] = []
    /// The request body. When present, a JSON content type is sent with it.
    var body: Data?
    /// Whether to attach a bearer token and the profile headers.
    var authenticated: Bool = true

    /// Whether to append the signed-in matricola as a query parameter.
    ///
    /// The rule the official client applies is to send it whenever the service's
    /// configured profile is non-zero. `iae` and `libretto` report profile `0` and need
    /// nothing; `ws_aule` reports `3`, and a rooms call without a matricola does not
    /// work.
    var sendsMatricola: Bool = false
    /// Overrides `poliAuthProfile` for this one call, or `nil` to use the value
    /// ``ServiceDirectory/profile(for:userProfile:)`` resolves.
    ///
    /// Exists for `ws_aule`, whose configured profile is one the signed-in account may
    /// not hold.
    var profileOverride: Int?
}

/// What can go wrong with one request.
///
/// ``isPermanent`` marks the cases that retrying or waiting cannot fix.
/// ``userFacingMessage(_:)`` decides which of these are worth telling the student
/// about.
nonisolated enum APIError: LocalizedError {
    /// An unhandled non-success status, with the first 300 bytes of the body.
    case badStatus(Int, body: String)
    /// The path answered 404: the service moved or was withdrawn. A different problem
    /// from the network being down.
    case endpointGone(String)
    /// The request was cancelled, almost always because the view that asked for it went
    /// away. Not a failure, and never shown to the student.
    case cancelled
    /// The account may not use this service, whatever its token says.
    ///
    /// Permanent for this student, so neither retrying nor signing in again helps.
    /// Carries the path and the first 200 bytes of the body.
    case notEntitled(String, body: String)
    /// The token is valid but was not minted with the scope this service requires.
    ///
    /// Reported upstream as a 401 mentioning “Scope OAuth non valido”. Refreshing
    /// cannot fix it, because scopes are fixed when a token is created; only a fresh
    /// sign-in helps.
    case invalidScope
    /// The request never completed, carrying the underlying error.
    case transport(any Error)
    /// The response arrived but would not decode into the expected shape.
    case decoding(any Error)
    /// The server kept answering with a 5xx status, carrying how many attempts were
    /// made.
    case retriesExhausted(Int)

    /// The localised sentence shown to the student.
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

    /// Whether retrying or waiting cannot help, because the endpoint or the
    /// authorisation is the problem.
    ///
    /// `true` for ``endpointGone(_:)``, ``invalidScope``, ``notEntitled(_:body:)``,
    /// ``cancelled``, and for a transport failure whose host does not resolve.
    var isPermanent: Bool {
        switch self {
        case .endpointGone, .invalidScope, .notEntitled, .cancelled: true
        case .transport(let error): (error as NSError).code == NSURLErrorCannotFindHost
        default: false
        }
    }
}

/// The sentence to show the student for an error, or `nil` when there is nothing to
/// say.
///
/// Cancellation returns `nil`: a request abandoned because its view went away is
/// not a failure, and ``Store`` reads this to decide whether a load failed at all.
///
/// - Parameter error: The error a load threw.
/// - Returns: The localised description, or `nil` for a cancellation.
nonisolated func userFacingMessage(_ error: any Error) -> String? {
    if let apiError = error as? APIError, case .cancelled = apiError { return nil }
    if PoliMiAPI.isCancellation(error) { return nil }
    return error.localizedDescription
}

/// The authenticated transport for every Politecnico backend.
///
/// Resolves a ``APIRequest`` against ``ServiceDirectory``, attaches the bearer token
/// and the two profile headers, sends it, and classifies what comes back.
///
/// ## Retries
///
/// A 5xx status or a transient transport failure is retried up to ``maxRetries``
/// times with a delay of 0.5, 1 then 2 seconds. Permanent failures — a host that
/// does not resolve, a bad URL, a TLS refusal, being offline — are not retried at
/// all.
///
/// ## The four kinds of 401
///
/// 1. A token that looks valid locally but is refused: refreshed once through
///    ``TokenStore/forceRefresh()`` and replayed.
/// 2. “Utente non abilitato”, recognised by ``isNotEntitled(_:)``: the account may
///    not use this service. Thrown as ``APIError/notEntitled(_:body:)`` without
///    re-authenticating, since a fresh sign-in grants the same account the same
///    services.
/// 3. A scope refusal, recognised by ``isInvalidScope(_:)``: reported as
///    ``APIError/invalidScope`` and escalated through `onInvalidScope` only for
///    hosts where ``ServiceDirectory/Service/refusalMeansBrokenSession`` holds.
/// 4. Anything else that survives a refresh, thrown as
///    ``APIError/badStatus(_:body:)`` with the body logged.
///
/// Conforms to ``HTTP`` through ``data(for:)``.
nonisolated final class PoliMiAPI: Sendable {
    /// The session requests are issued through.
    private let session: URLSession
    /// Supplies and refreshes the bearer token.
    private let tokens: TokenStore
    /// Resolves hosts to base URLs and supplies the profile values.
    private let directory: ServiceDirectory
    /// Diagnostic log for this type, under the `api` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "api")

    /// How many times a retryable failure is re-attempted.
    private let maxRetries = 3

    /// Supplies the signed-in student's `poliAuthProfile`.
    ///
    /// Injected because the value is only known after sign-in, and this type is built
    /// before it.
    private let profileID: @Sendable () async -> Int

    /// Supplies the matricola for requests with ``APIRequest/sendsMatricola`` set.
    /// Injected for the same reason as ``profileID``.
    private let matricola: @Sendable () async -> String?

    /// Called when a service the app depends on refuses the token's scopes, so the app
    /// can drop the token and send the student back to sign-in.
    private let onInvalidScope: @Sendable () async -> Void

    /// Creates the authenticated transport.
    ///
    /// - Parameters:
    ///   - tokens: Supplies and refreshes the bearer token.
    ///   - directory: Resolves hosts and profile values.
    ///   - profileID: Supplies the signed-in student's profile.
    ///   - matricola: Supplies the matricola, for the services that require it.
    ///   - onInvalidScope: Called on a scope refusal from a service the app depends on.
    ///   - session: The session requests are issued through.
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

    /// Whether a 401 body reports that the token's scopes are wrong.
    ///
    /// Matched on the message, because the status code is the same 401 used for an
    /// ordinary expired token and the two need opposite responses: a refresh for one, a
    /// fresh sign-in for the other. A body that ``isNotEntitled(_:)`` claims is never
    /// treated as a scope failure.
    ///
    /// - Parameter body: The response body.
    /// - Returns: `true` when the body names an invalid scope or a
    ///   `JafUnauthorizedException`.
    static func isInvalidScope(_ body: String) -> Bool {
        guard !isNotEntitled(body) else { return false }
        return body.localizedCaseInsensitiveContains("Scope OAuth non valido")
            || body.localizedCaseInsensitiveContains("JafUnauthorizedException")
    }

    /// Whether a 401 body reports that this account may not use the service, as
    /// distinct from the token being no good.
    ///
    /// Both arrive as 401 `JafUnauthorizedException`, and only the message tells them
    /// apart. The code match is anchored so that `Code: 60` and `Code: 66` are not read
    /// as `Code: 6`, which would report a genuine session failure as a permissions one
    /// and never offer the sign-in that would fix it.
    ///
    /// - Parameter body: The response body.
    /// - Returns: `true` when the body says “Utente non abilitato” or carries
    ///   `Code: 6`.
    static func isNotEntitled(_ body: String) -> Bool {
        if body.localizedCaseInsensitiveContains("Utente non abilitato") { return true }
        // Anchored: a plain `contains("Code: 6")` also matches `Code: 60` and
        // `Code: 66`, which would read a genuine session failure as a
        // permissions one and never offer the login that would fix it.
        return body.range(of: "Code:\\s*6(?![0-9])", options: .regularExpression) != nil
    }

    /// Sends a request and decodes its response off the main actor, with ISO 8601
    /// dates.
    ///
    /// A decoding failure logs the first 1200 bytes of the body, since an endpoint that
    /// moves usually changes shape with it.
    ///
    /// - Parameters:
    ///   - request: What to fetch.
    ///   - type: The shape to decode.
    /// - Returns: The decoded value.
    /// - Throws: ``APIError/decoding(_:)`` when the body will not decode, or any error
    ///   ``send(_:)`` raises.
    func send<T: Decodable & Sendable>(_ request: APIRequest, as type: T.Type) async throws -> T {
        let data = try await send(request)
        do {
            return try await BackgroundJSON.decode(T.self, from: data, iso8601Dates: true)
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

    /// Sends a request and returns its body, handling retries and the 401 cases.
    ///
    /// - Parameter request: What to fetch.
    /// - Returns: The response body. A response that is not an `HTTPURLResponse` is
    ///   returned as-is.
    /// - Throws: ``APIError`` or ``AuthError``. See the type's discussion for how each
    ///   status is classified.
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

    /// ``isRetryable(_:)``, exposed for tests.
    ///
    /// - Parameter error: The transport error to classify.
    /// - Returns: `true` when another attempt is worthwhile.
    static func isRetryableForTesting(_ error: any Error) -> Bool { isRetryable(error) }

    /// Which of the official app's two HTTP clients serves a request.
    ///
    /// The `jaf` layer and the `iae`, `libretto` and `ws_aule` services go through
    /// axios; the `/v1/*` app endpoints and the agenda go through openapi-fetch. They
    /// differ only in how they treat `poliAuthD_profile` — see
    /// ``makeURLRequest(_:)``.
    ///
    /// - Parameter request: The request to classify.
    /// - Returns: `true` for the axios-served hosts and paths.
    static func usesAxiosClient(_ request: APIRequest) -> Bool {
        switch request.host {
        case .iae, .libretto, .wsAule: true
        case .app: request.path.hasPrefix("/jaf/")
        // `maps` never reaches this client — it is unauthenticated and goes
        // through ``PublicHTTP`` — but the answer is the same as the agenda's.
        case .agenda, .weBeep, .maps: false
        }
    }

    /// Whether an error is the task being cancelled rather than anything going wrong.
    ///
    /// Cancellation arrives in two shapes — Swift's `CancellationError` and `URLError`
    /// −999 — and both mean the caller stopped waiting, not that the Politecnico is
    /// unreachable.
    ///
    /// - Parameter error: The error to classify.
    /// - Returns: `true` for either shape.
    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    /// Whether a transport failure is worth another attempt.
    ///
    /// Timeouts, a refused connection, a lost connection, a DNS lookup failure and an
    /// unavailable resource are transient. A host that does not resolve, a malformed or
    /// unsupported URL, being offline, a cancellation and every TLS failure are
    /// verdicts rather than hiccups, and are not retried. Anything outside the URL error
    /// domain is not retried.
    ///
    /// - Parameter error: The transport error to classify.
    /// - Returns: `true` when another attempt is worthwhile.
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

    /// Builds the `URLRequest` for a request: base URL, query, body, headers, token and
    /// a 30-second timeout.
    ///
    /// ## The profile headers
    ///
    /// `poliAuthProfile` carries the service's own profile where `props` declares one,
    /// and the signed-in student's otherwise, unless ``APIRequest/profileOverride``
    /// supplies a value.
    ///
    /// `poliAuthD_profile` carries the account's secondary profile when it has one.
    /// When it does not, the axios-served paths receive the literal sentinel
    /// ``PoliMiProfile/emptyDProfile`` and the openapi-fetch paths receive no header at
    /// all — matching the two official clients. See ``usesAxiosClient(_:)``.
    ///
    /// - Parameter request: What to fetch.
    /// - Returns: The prepared request.
    /// - Throws: Whatever ``TokenStore/validToken()`` raises for an authenticated
    ///   request.
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

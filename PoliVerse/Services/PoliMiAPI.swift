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
}

nonisolated enum APIError: LocalizedError {
    case badStatus(Int, body: String)
    /// The path returned 404 — the service moved or was withdrawn, which is a
    /// different problem from the network being down and deserves saying so.
    case endpointGone(String)
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
        case .badStatus(let code, _): "Il server ha risposto \(code)."
        case .endpointGone: "Questo servizio del Politecnico non è più disponibile a questo indirizzo."
        case .invalidScope: "L'accesso è scaduto. Accedi di nuovo per continuare."
        case .transport: "Impossibile raggiungere i server del Politecnico."
        case .decoding: "Risposta del server non leggibile."
        case .retriesExhausted(let n): "Nessuna risposta dopo \(n) tentativi."
        }
    }

    /// True when retrying or waiting will not help — the endpoint itself is the
    /// problem.
    var isPermanent: Bool {
        switch self {
        case .endpointGone, .invalidScope: true
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

    /// Called when the server says the token's scopes are wrong, so the app can
    /// drop it and send the user back to login rather than retrying forever.
    private let onInvalidScope: @Sendable () async -> Void

    init(
        tokens: TokenStore,
        directory: ServiceDirectory,
        profileID: @escaping @Sendable () async -> Int = { PoliMiProfile.student },
        onInvalidScope: @escaping @Sendable () async -> Void = {},
        session: URLSession = .shared
    ) {
        self.tokens = tokens
        self.directory = directory
        self.profileID = profileID
        self.onInvalidScope = onInvalidScope
        self.session = session
    }

    /// Recognises the backends' "wrong scopes" 401.
    ///
    /// Matched on the message because the status code and `statusCode` field
    /// are the same 401 used for an ordinary expired token, and the two need
    /// opposite responses: refresh for one, re-login for the other.
    static func isInvalidScope(_ body: String) -> Bool {
        body.localizedCaseInsensitiveContains("Scope OAuth non valido")
            || body.localizedCaseInsensitiveContains("JafUnauthorizedException")
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
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
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

                case 401 where Self.isInvalidScope(String(data: data, encoding: .utf8) ?? ""):
                    let body = String(data: data, encoding: .utf8) ?? ""
                    log.error("""
                        Token rejected for scope — path=\(request.path, privacy: .public) \
                        body=\(String(body.prefix(200)), privacy: .public)
                        """)
                    await onInvalidScope()
                    throw APIError.invalidScope

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

    /// Whether a transport failure is worth another attempt.
    ///
    /// DNS and TLS failures are verdicts, not hiccups. Treating them as
    /// transient produced six round trips per request against a host that no
    /// longer exists.
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
        if !request.query.isEmpty { components.queryItems = request.query }

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
            // The value is the *user's* profile, from `/jaf/internal/profiles`:
            //
            //   L_e = n => n === 1   // student
            //   T_e = n => n === 4   // alumni
            //
            // Not to be confused with the `iae.profile` / `libretto.profile`
            // in `props`, which are 0 and mean something else entirely — they
            // decide whether a call appends a `matricola` query parameter.
            // Sending 0 here identifies no known profile at all.
            urlRequest.setValue(String(await profileID()), forHTTPHeaderField: "poliAuthProfile")
        }
        urlRequest.timeoutInterval = 30
        return urlRequest
    }
}

import Foundation
import OSLog

/// The three hosts the Politecnico exposes. PoliFemo hardcoded a `staging`
/// PoliNetwork URL into shipping builds; keeping them in one enum makes that
/// mistake visible.
nonisolated enum APIHost {
    /// Main app backend: user info, gradebook, timetable.
    case app
    /// Exams/teachings backend (`iae`). Same bearer token, different origin.
    case exams
    /// Moodle instance backing WeBeep.
    case weBeep

    var baseURL: URL {
        switch self {
        case .app: URL(string: "https://polimiapp.polimi.it/polimi_app")!
        case .exams: URL(string: "https://www22.dmz.polimi.it/iae")!
        case .weBeep: URL(string: "https://webeep.polimi.it")!
        }
    }
}

nonisolated struct APIRequest {
    var host: APIHost
    var path: String
    var method: String = "GET"
    var query: [URLQueryItem] = []
    var body: Data?
    var authenticated: Bool = true
}

nonisolated enum APIError: LocalizedError {
    case badStatus(Int, body: String)
    /// The path returned 404 — the service moved or was withdrawn, which is a
    /// different problem from the network being down and deserves saying so.
    case endpointGone(String)
    case transport(any Error)
    case decoding(any Error)
    case retriesExhausted(Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, _): "Il server ha risposto \(code)."
        case .endpointGone: "Questo servizio del Politecnico non è più disponibile a questo indirizzo."
        case .transport: "Impossibile raggiungere i server del Politecnico."
        case .decoding: "Risposta del server non leggibile."
        case .retriesExhausted(let n): "Nessuna risposta dopo \(n) tentativi."
        }
    }

    /// True when retrying or waiting will not help — the endpoint itself is the
    /// problem.
    var isPermanent: Bool {
        switch self {
        case .endpointGone: true
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
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "api")

    private let maxRetries = 3

    init(tokens: TokenStore, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
    }

    func send<T: Decodable>(_ request: APIRequest, as type: T.Type) async throws -> T {
        let data = try await send(request)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            log.error("Decoding \(String(describing: T.self)) failed: \(error)")
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
                    log.error("Endpoint gone: \(request.host.baseURL.absoluteString)\(request.path)")
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
        var components = URLComponents(
            url: request.host.baseURL.appendingPathComponent(request.path),
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
        }
        urlRequest.timeoutInterval = 30
        return urlRequest
    }
}

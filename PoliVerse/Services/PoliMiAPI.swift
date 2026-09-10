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
    case transport(any Error)
    case decoding(any Error)
    case retriesExhausted(Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, _): "Il server ha risposto \(code)."
        case .transport: "Connessione non riuscita."
        case .decoding: "Risposta del server non leggibile."
        case .retriesExhausted(let n): "Nessuna risposta dopo \(n) tentativi."
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

                default:
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw APIError.badStatus(http.statusCode, body: String(body.prefix(300)))
                }
            } catch let error as APIError {
                throw error
            } catch let error as AuthError {
                throw error
            } catch {
                attempt += 1
                guard attempt <= maxRetries else { throw APIError.transport(error) }
                try await Task.sleep(nanoseconds: UInt64(0.5 * pow(2, Double(attempt - 1)) * 1_000_000_000))
            }
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

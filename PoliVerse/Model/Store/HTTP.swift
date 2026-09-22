import Foundation

/// How everything in the model layer reaches the network.
///
/// One method, because that is the whole of what a caller needs: the bytes for a
/// request, or an error. Decoding belongs to the caller; tokens, retries and scope
/// handling belong to the adapter.
///
/// Three adapters conform: ``PoliMiAPI`` for authenticated services, ``PublicHTTP``
/// for the ones that take no token, and ``FixtureHTTP`` for tests and previews.
nonisolated protocol HTTP: Sendable {
    /// Performs a request and returns its body.
    ///
    /// - Parameter request: What to fetch.
    /// - Returns: The response body.
    /// - Throws: ``APIError``, including ``APIError/cancelled`` when the task is
    ///   cancelled.
    func data(for request: APIRequest) async throws -> Data
}

/// The authenticated adapter: tokens, retries, scope handling and typed errors.
extension PoliMiAPI: HTTP {
    /// Sends the request through the authenticated pipeline.
    ///
    /// - Parameter request: What to fetch.
    /// - Returns: The response body.
    /// - Throws: ``APIError``.
    func data(for request: APIRequest) async throws -> Data {
        try await send(request)
    }
}

/// The unauthenticated adapter, for services that take no token.
///
/// The campus map, the manifesti pages and the rooms endpoints are public, so
/// routing them through ``PoliMiAPI`` would make a catalogue anyone can read wait
/// on a sign-in it does not need. Going through ``HTTP`` all the same keeps them
/// substitutable in tests and previews.
///
/// Base URLs come from a ``ServiceDirectory`` when one is supplied, and from
/// ``APIRequest/Host/fallback`` otherwise.
nonisolated struct PublicHTTP: HTTP {
    /// The session requests are issued through.
    private let session: URLSession
    /// Resolves a host to its current base URL. When `nil`, each host's fallback is
    /// used.
    private let directory: ServiceDirectory?

    /// Creates the unauthenticated adapter.
    ///
    /// - Parameters:
    ///   - session: The session requests are issued through.
    ///   - directory: Resolves hosts to base URLs. Omit to use each host's fallback.
    init(session: URLSession = .shared, directory: ServiceDirectory? = nil) {
        self.session = session
        self.directory = directory
    }

    /// Performs an unauthenticated request with a 30-second timeout.
    ///
    /// - Parameter request: What to fetch.
    /// - Returns: The response body. A response that is not an `HTTPURLResponse` is
    ///   returned as-is.
    /// - Throws: ``APIError/endpointGone(_:)`` for a malformed URL or a 404,
    ///   ``APIError/badStatus(_:body:)`` for any other non-2xx status with the first
    ///   1200 bytes of the body, ``APIError/cancelled`` for a cancellation, and
    ///   ``APIError/transport(_:)`` for anything else.
    func data(for request: APIRequest) async throws -> Data {
        let base = await directory?.baseURL(for: request.host) ?? request.host.fallback
        guard var components = URLComponents(
            url: base.appendingPathComponent(request.path), resolvingAgainstBaseURL: false)
        else { throw APIError.endpointGone(request.path) }
        components.queryItems = request.query.isEmpty ? nil : request.query
        guard let url = components.url else { throw APIError.endpointGone(request.path) }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { return data }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 404 { throw APIError.endpointGone(request.path) }
                let body = String(data: data.prefix(1200), encoding: .utf8) ?? "<binary>"
                throw APIError.badStatus(http.statusCode, body: body)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            if PoliMiAPI.isCancellation(error) { throw APIError.cancelled }
            throw APIError.transport(error)
        }
    }
}

/// The adapter tests and previews substitute: canned bytes, no network.
///
/// An actor so that it can record what was asked of it without a lock. The
/// recording in ``requests`` is most of what a test asserts on, since whether a
/// source asked for the right path with the right query is not something a decoder
/// test can reach.
actor FixtureHTTP: HTTP {
    /// What a fixture adapter raises on its own behalf.
    enum Failure: Error, Equatable {
        /// No fixture was registered for this path and no fallback was supplied.
        case noFixture(String)
    }

    /// Every request made, in order, for assertions.
    private(set) var requests: [APIRequest] = []

    /// Canned responses, keyed by ``APIRequest/path``.
    private let responses: [String: Result<Data, any Error>]
    /// Answers any path with no fixture of its own. `nil` throws
    /// ``Failure/noFixture(_:)`` instead.
    private let fallback: Result<Data, any Error>?

    /// Creates a fixture adapter.
    ///
    /// - Parameters:
    ///   - responses: Canned bodies keyed by path, spelled exactly as
    ///     ``APIRequest/path`` spells it.
    ///   - fallback: Answers any path not in `responses`.
    init(_ responses: [String: Data] = [:], fallback: Result<Data, any Error>? = nil) {
        self.responses = responses.mapValues { .success($0) }
        self.fallback = fallback
    }

    /// A fixture adapter that answers every path with the same failure, for exercising
    /// error branches where which path failed is beside the point.
    ///
    /// - Parameter error: What every request throws.
    /// - Returns: The adapter.
    static func failing(_ error: any Error) -> FixtureHTTP {
        FixtureHTTP(fallback: .failure(error))
    }

    /// Records the request and answers it from the fixtures.
    ///
    /// - Parameter request: What to fetch.
    /// - Returns: The canned body for this path, or the fallback's.
    /// - Throws: The canned error, or ``Failure/noFixture(_:)`` when neither a fixture
    ///   nor a fallback covers the path.
    func data(for request: APIRequest) async throws -> Data {
        requests.append(request)
        switch responses[request.path] ?? fallback {
        case .success(let data): return data
        case .failure(let error): throw error
        case nil: throw Failure.noFixture(request.path)
        }
    }
}

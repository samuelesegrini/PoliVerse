import Foundation

/// How anything in the model layer reaches the network.
///
/// The app had sixteen files building their own `URLSession` — the authenticated
/// services through ``PoliMiAPI``, and the public ones (maps, manifesti, WeBeep)
/// each rolling their own. There was therefore no single place to change a
/// timeout, add a header, or hand a caller a recorded response instead of a real
/// one. The last of those is why only one of a hundred test files could build a
/// model at all: every model reached the network in its initialiser's shadow,
/// and nothing could get between.
///
/// One method, because that is the whole of what a caller needs: give me the
/// bytes for this request, or throw. Decoding belongs to the caller, retries and
/// auth belong to the adapter.
nonisolated protocol HTTP: Sendable {
    func data(for request: APIRequest) async throws -> Data
}

/// The authenticated adapter: tokens, retries, scope handling, typed errors.
extension PoliMiAPI: HTTP {
    func data(for request: APIRequest) async throws -> Data {
        try await send(request)
    }
}

/// The adapter tests and previews swap in: canned bytes, no network.
///
/// An actor so that it can record what was asked of it without a lock; the
/// recording is most of what a test wants to assert, since "did this source ask
/// for the right path with the right query" is the part a decoder test cannot
/// reach.
actor FixtureHTTP: HTTP {
    enum Failure: Error, Equatable {
        /// No fixture was registered for this path, which is nearly always a
        /// test naming the wrong one rather than a behaviour worth exercising.
        case noFixture(String)
    }

    /// Every request made, in order, for assertions.
    private(set) var requests: [APIRequest] = []

    private let responses: [String: Result<Data, any Error>]
    /// Answers any path with no fixture of its own. Nil means "throw
    /// ``Failure/noFixture(_:)``", which is what an unprepared test deserves.
    private let fallback: Result<Data, any Error>?

    /// - Parameter responses: keyed by path, exactly as ``APIRequest/path``
    ///   spells it.
    init(_ responses: [String: Data] = [:], fallback: Result<Data, any Error>? = nil) {
        self.responses = responses.mapValues { .success($0) }
        self.fallback = fallback
    }

    /// Answers every path with the same failure. For the error branches, where
    /// which path failed is beside the point.
    static func failing(_ error: any Error) -> FixtureHTTP {
        FixtureHTTP(fallback: .failure(error))
    }

    func data(for request: APIRequest) async throws -> Data {
        requests.append(request)
        switch responses[request.path] ?? fallback {
        case .success(let data): return data
        case .failure(let error): throw error
        case nil: throw Failure.noFixture(request.path)
        }
    }
}

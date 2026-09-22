import Foundation

/// Asks each service whether it is there, and how long it takes to say so.
///
/// From a student's side, “it will not load” is three situations needing three answers:
/// their network cannot reach the Politecnico, the Politecnico answers with a fault, or
/// the service is fine and the problem is elsewhere. This separates them.
///
/// Probes a base address with `HEAD` and no credentials. That proves reachability, not
/// that a request carrying a token would succeed — which is deliberate: the token's side
/// is what ``ScopeAudit`` reports, and a probe must never send a credential to a host it
/// is testing.
nonisolated struct ConnectionProbe: Sendable {
    /// What one probe found.
    struct Result: Equatable, Sendable {
        /// How a service answered.
        enum Verdict: Equatable, Sendable {
            /// The server answered with a status below 500. Base addresses are not pages, so a 401
            /// or a 404 still means the service is there.
            case reachable(status: Int)
            /// The server answered with a fault of its own.
            case serverFault(status: Int)
            /// No answer within the timeout.
            case timedOut
            /// No answer at all: no route, no name, or no TLS.
            case unreachable(URLError.Code)
        }

        /// How the service answered.
        let verdict: Verdict
        /// Request to response. `nil` when nothing came back.
        let latency: Duration?

        /// ``latency`` in whole milliseconds, as the page and the report print it.
        var milliseconds: Int? {
            latency.map { duration in
                let (seconds, attoseconds) = duration.components
                return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
            }
        }
    }

    /// The session probes are issued through.
    private let session: URLSession
    /// How long to wait for an answer.
    private let timeout: TimeInterval

    /// Creates a prober.
    ///
    /// - Parameters:
    ///   - session: The session probes are issued through.
    ///   - timeout: Long enough for a slow campus network, short enough that a dead service
    ///     does not hold the whole check for a minute.
    init(session: URLSession = .shared, timeout: TimeInterval = 8) {
        self.session = session
        self.timeout = timeout
    }

    /// Probes one address with an uncached, credential-free `HEAD`.
    ///
    /// - Parameter url: The base address to probe.
    /// - Returns: How it answered, and how long it took. Never throws.
    func probe(_ url: URL) async -> Result {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let (_, response) = try await session.data(for: request)
            let latency = clock.now - start
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Result(verdict: status >= 500 ? .serverFault(status: status) : .reachable(status: status),
                          latency: latency)
        } catch let error as URLError where error.code == .timedOut {
            return Result(verdict: .timedOut, latency: nil)
        } catch let error as URLError {
            return Result(verdict: .unreachable(error.code), latency: nil)
        } catch {
            return Result(verdict: .unreachable(.unknown), latency: nil)
        }
    }

    /// Probes several addresses at once.
    ///
    /// - Parameter urls: The base addresses to probe.
    /// - Returns: The results in the order asked, whatever order the network answers in.
    func probe(_ urls: [URL]) async -> [Result] {
        await withTaskGroup(of: (Int, Result).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask { (index, await probe(url)) }
            }
            var results = [Result?](repeating: nil, count: urls.count)
            for await (index, result) in group { results[index] = result }
            return results.compactMap(\.self)
        }
    }
}

import Foundation

/// Asks each service whether it is there, and how long it takes to say so.
///
/// Everything else in the app reports failures after the fact and in the
/// app's words. From a student's side, "non carica" is three different
/// situations that need three different answers: their network cannot reach
/// the Politecnico, the Politecnico answers with a fault, or the service is
/// fine and the problem is elsewhere. This separates them.
///
/// Probes the base address with a `HEAD` and no credentials. That proves
/// reachability, not that a request *with* a token would succeed — which is
/// deliberate: the token's side is what ``ScopeAudit`` and the session rows
/// report, and a probe must never send a credential to a host it is testing.
nonisolated struct ConnectionProbe: Sendable {
    struct Result: Equatable, Sendable {
        enum Verdict: Equatable, Sendable {
            /// The server answered with a status below 500. Base addresses
            /// are not pages, so a 401 or a 404 still means "it is there".
            case reachable(status: Int)
            /// The server answered, with a fault of its own.
            case serverFault(status: Int)
            /// No answer in time.
            case timedOut
            /// No answer at all: no route, no name, no TLS.
            case unreachable(URLError.Code)
        }

        let verdict: Verdict
        /// Request to response. Nil when nothing came back.
        let latency: Duration?

        /// The latency in whole milliseconds, as the page and the report say it.
        var milliseconds: Int? {
            latency.map { duration in
                let (seconds, attoseconds) = duration.components
                return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
            }
        }
    }

    private let session: URLSession
    private let timeout: TimeInterval

    /// - Parameter timeout: long enough for a slow campus Wi-Fi, short enough
    ///   that a dead service does not hold the whole check for a minute.
    init(session: URLSession = .shared, timeout: TimeInterval = 8) {
        self.session = session
        self.timeout = timeout
    }

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

    /// Probes all at once and answers in the order asked, whatever order the
    /// network answers in.
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

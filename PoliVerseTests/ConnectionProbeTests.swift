import Foundation
import Testing
@testable import PoliVerse

/// "Verifica collegamenti" exists to tell three situations apart that all look
/// like "non carica" from inside the app: the student's network cannot reach
/// the Politecnico, the Politecnico answers with an error, or the service is
/// fine. These pin the line between them.
@Suite("Verifica dei collegamenti")
struct ConnectionProbeTests {
    private func probe(answering answer: StubProtocol.Answer) async -> ConnectionProbe.Result {
        let host = "probe-\(UUID().uuidString).test"
        StubProtocol.set(answer, for: host)
        defer { StubProtocol.clear(host) }
        return await ConnectionProbe(session: StubProtocol.session).probe(URL(string: "https://\(host)/rest")!)
    }

    @Test("Un servizio che risponde 200 è raggiungibile, con il tempo di risposta")
    func okIsReachable() async {
        let result = await probe(answering: .status(200))
        #expect(result.verdict == .reachable(status: 200))
        #expect(result.latency != nil)
    }

    /// Base addresses are not pages: many answer 404 or 401 at the root while
    /// the service behind them works. The server answering is what counts.
    @Test("Anche un 404 dimostra che il servizio risponde")
    func clientErrorIsReachable() async {
        let result = await probe(answering: .status(404))
        #expect(result.verdict == .reachable(status: 404))
    }

    @Test("Un 5xx è un guasto del server, non della rete")
    func serverErrorIsAFault() async {
        let result = await probe(answering: .status(503))
        #expect(result.verdict == .serverFault(status: 503))
        #expect(result.latency != nil)
    }

    @Test("Un timeout è detto come tale, senza tempo di risposta")
    func timeout() async {
        let result = await probe(answering: .failure(.timedOut))
        #expect(result.verdict == .timedOut)
        #expect(result.latency == nil)
    }

    @Test("Un indirizzo che non si risolve è irraggiungibile, con il motivo")
    func unreachable() async {
        let result = await probe(answering: .failure(.cannotFindHost))
        #expect(result.verdict == .unreachable(.cannotFindHost))
        #expect(result.latency == nil)
    }

    /// The page lists services in a fixed order; answers arrive in whatever
    /// order the network delivers them.
    @Test("Più servizi insieme tornano nell’ordine chiesto")
    func manyInOrder() async {
        let slow = "slow-\(UUID().uuidString).test", fast = "fast-\(UUID().uuidString).test"
        StubProtocol.set(.status(200, delay: 0.3), for: slow)
        StubProtocol.set(.status(503), for: fast)
        defer { StubProtocol.clear(slow); StubProtocol.clear(fast) }

        let results = await ConnectionProbe(session: StubProtocol.session).probe([
            URL(string: "https://\(slow)/")!, URL(string: "https://\(fast)/")!,
        ])
        #expect(results.map(\.verdict) == [.reachable(status: 200), .serverFault(status: 503)])
    }
}

/// Answers requests by host, so tests running in parallel never read each
/// other's answers.
nonisolated final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Answer: Sendable {
        case status(Int, delay: TimeInterval = 0)
        case failure(URLError.Code)
    }

    nonisolated(unsafe) private static var answers: [String: Answer] = [:]
    private static let lock = NSLock()

    static func set(_ answer: Answer, for host: String) {
        lock.withLock { answers[host] = answer }
    }

    static func clear(_ host: String) {
        lock.withLock { _ = answers.removeValue(forKey: host) }
    }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let host = request.url?.host() ?? ""
        guard let answer = Self.lock.withLock({ Self.answers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        switch answer {
        case .status(let code, let delay):
            let respond = { [self] in
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
            }
            if delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: respond)
            } else {
                respond()
            }
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }
}

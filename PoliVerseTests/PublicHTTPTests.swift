import Foundation
import Testing
@testable import PoliVerse

/// The unauthenticated adapter, which four models now go through instead of
/// each building its own `URLSession` against a hardcoded host.
///
/// Worth testing directly rather than only through its callers: it is the one
/// place that turns an ``APIRequest`` into a URL, and getting that wrong is a
/// class of bug that shows up as "the service returned nothing" rather than as
/// an error anyone can read.
/// Serialised: the stub below is one shared `URLProtocol` with static state,
/// and Swift Testing runs a suite's tests in parallel by default — which had
/// one test's 404 arriving in another's URL assertion.
@Suite("Public HTTP", .serialized)
struct PublicHTTPTests {
    private func client() -> PublicHTTP {
        PublicHTTP(session: RecordingStub.session)
    }

    @Test("The service's base, the path and the query are joined into one URL")
    func buildsTheURL() async throws {
        RecordingStub.reset(body: "[]")
        _ = try await client().data(for: APIRequest(
            host: .maps, path: "/spazi/edificio/geojson",
            query: [.init(name: "filter", value: "")], authenticated: false))

        let url = try #require(RecordingStub.lastURL)
        #expect(url.absoluteString
            == "https://onlineservices.polimi.it/maps_rest/rest/spazi/edificio/geojson?filter=")
    }

    /// The map service would otherwise be a fifth hardcoded copy of this host.
    @Test("The maps base comes from the directory, not from a call site")
    func mapsBaseIsInTheDirectory() {
        #expect(ServiceDirectory.Service.maps.fallback.absoluteString
                == "https://onlineservices.polimi.it/maps_rest/rest")
        // Public, so a refusal from it says nothing about the session.
        #expect(ServiceDirectory.Service.maps.refusalMeansBrokenSession == false)
        #expect(ServiceDirectory.Service.maps.propsKey == nil)
    }

    @Test("A request with no query carries no question mark")
    func omitsAnEmptyQuery() async throws {
        RecordingStub.reset(body: "[]")
        _ = try await client().data(for: APIRequest(host: .maps, path: "/spazi/aula",
                                                    authenticated: false))

        let url = try #require(RecordingStub.lastURL)
        #expect(url.absoluteString == "https://onlineservices.polimi.it/maps_rest/rest/spazi/aula")
    }

    /// A withdrawn endpoint is worth saying plainly rather than as a generic
    /// failure: it means the service moved, not that the network is down.
    @Test("A 404 is reported as a withdrawn endpoint")
    func notFoundIsEndpointGone() async {
        RecordingStub.reset(body: "nope", status: 404)
        await #expect(throws: APIError.self) {
            try await client().data(for: APIRequest(host: .maps, path: "/gone",
                                                    authenticated: false))
        }
    }

    @Test("Another failing status carries the code and the body")
    func badStatusCarriesTheBody() async throws {
        RecordingStub.reset(body: "server is unwell", status: 503)
        do {
            _ = try await client().data(for: APIRequest(host: .maps, path: "/spazi/aula",
                                                        authenticated: false))
            Issue.record("Expected a failure")
        } catch let error as APIError {
            guard case .badStatus(let code, let body) = error else {
                Issue.record("Expected badStatus, got \(error)")
                return
            }
            #expect(code == 503)
            #expect(body.contains("unwell"))
        }
    }

    /// A request abandoned because its view went away is not a failure, and
    /// must never reach the student as one.
    @Test("A cancelled transport error is reported as cancellation")
    func cancellationIsItsOwnError() async throws {
        RecordingStub.reset(failure: .cancelled)
        do {
            _ = try await client().data(for: APIRequest(host: .maps, path: "/spazi/aula",
                                                        authenticated: false))
            Issue.record("Expected a failure")
        } catch let error as APIError {
            guard case .cancelled = error else {
                Issue.record("Expected cancelled, got \(error)")
                return
            }
            #expect(userFacingMessage(error) == nil)
        }
    }

    @Test("A transport failure is wrapped rather than leaking URLError")
    func transportIsWrapped() async throws {
        RecordingStub.reset(failure: .notConnectedToInternet)
        do {
            _ = try await client().data(for: APIRequest(host: .maps, path: "/spazi/aula",
                                                        authenticated: false))
            Issue.record("Expected a failure")
        } catch let error as APIError {
            guard case .transport = error else {
                Issue.record("Expected transport, got \(error)")
                return
            }
            #expect(userFacingMessage(error) != nil)
        }
    }
}

/// Records the URL it was asked for and answers with whatever was set.
nonisolated final class RecordingStub: URLProtocol, @unchecked Sendable {
    private enum Answer: Sendable {
        case body(String, status: Int)
        case failure(URLError.Code)
    }

    nonisolated(unsafe) private static var answer: Answer = .body("[]", status: 200)
    nonisolated(unsafe) private static var url: URL?
    private static let lock = NSLock()

    static func reset(body: String, status: Int = 200) {
        lock.withLock {
            answer = .body(body, status: status)
            url = nil
        }
    }

    static func reset(failure code: URLError.Code) {
        lock.withLock {
            answer = .failure(code)
            url = nil
        }
    }

    static var lastURL: URL? { lock.withLock { url } }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let current = Self.lock.withLock { () -> Answer in
            Self.url = request.url
            return Self.answer
        }
        switch current {
        case .body(let json, let status):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }
}

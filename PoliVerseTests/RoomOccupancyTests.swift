import Foundation
import Testing
@testable import PoliVerse

/// The occupancy endpoint, which both the app and the widget call.
///
/// The rule it exists to keep: "we cannot tell" is never reported as "the room
/// is free". A hidden room, a server error and a broken body all have to stay
/// distinguishable from an empty list of bookings, because the difference is
/// someone walking into a lecture.
@Suite("Occupazione delle aule")
struct RoomOccupancyTests {
    private let day = PoliMiDate.time(0, on: Date(timeIntervalSince1970: 1_772_000_000))

    /// The stub answers by occupancy id, and each call uses one of its own,
    /// so tests running in parallel never read each other's answers.
    private func fetch(_ answer: OccupancyStub.Answer) async -> RoomOccupancy.Result {
        let id = UUID().uuidString
        OccupancyStub.set(answer, for: id)
        defer { OccupancyStub.clear(id) }
        return await RoomOccupancy.fetch(occupancyID: id, on: day, session: OccupancyStub.session)
    }

    @Test("Le fasce occupate tornano come intervalli su quel giorno")
    func busyBands() async throws {
        let result = await fetch(.body(#"[{"inizio":"08:15","fine":"10:15"},{"inizio":"14:30","fine":"16:00"}]"#))
        guard case .busy(let intervals) = result else {
            Issue.record("Atteso .busy, ottenuto \(result)")
            return
        }
        #expect(intervals.count == 2)

        let calendar = PoliMiDate.romeCalendar
        let first = try #require(intervals.first)
        #expect(calendar.component(.hour, from: first.start) == 8)
        #expect(calendar.component(.minute, from: first.start) == 15)
        #expect(calendar.component(.hour, from: first.end) == 10)
        #expect(calendar.isDate(first.start, inSameDayAs: day), "La fascia è finita su un altro giorno")
    }

    /// An empty list is a real answer: the room is free all day. It must not
    /// be confused with a failure.
    @Test("Nessuna fascia significa aula libera, non errore")
    func noBands() async {
        let result = await fetch(.body("[]"))
        guard case .busy(let intervals) = result else {
            Issue.record("Atteso .busy, ottenuto \(result)")
            return
        }
        #expect(intervals.isEmpty)
    }

    /// `MSG_OCCUPAZIONI_NASCOSTE`: the university does not publish this room's
    /// bookings. Its own case, so the screen can say so rather than show it
    /// free.
    @Test("Un’aula con occupazioni nascoste è detta tale")
    func hidden() async {
        let result = await fetch(.body(#"{"messaggio":"MSG_OCCUPAZIONI_NASCOSTE"}"#))
        guard case .hidden = result else {
            Issue.record("Atteso .hidden, ottenuto \(result)")
            return
        }
    }

    @Test("Un errore del server è un fallimento, non un’aula vuota")
    func serverError() async {
        let result = await fetch(.body("[]", status: 503))
        guard case .failed = result else {
            Issue.record("Atteso .failed, ottenuto \(result)")
            return
        }
    }

    @Test("Un corpo illeggibile è un fallimento")
    func brokenBody() async {
        let result = await fetch(.body("<html>errore</html>"))
        guard case .failed = result else {
            Issue.record("Atteso .failed, ottenuto \(result)")
            return
        }
    }

    @Test("Una rete che non risponde è un fallimento")
    func networkFailure() async {
        let result = await fetch(.failure(.timedOut))
        guard case .failed = result else {
            Issue.record("Atteso .failed, ottenuto \(result)")
            return
        }
    }

    // MARK: Le fasce

    /// A band missing one of its two times cannot be placed on the day, and is
    /// dropped rather than guessed at.
    @Test("Una fascia senza uno dei due orari viene scartata")
    func incompleteBand() {
        #expect(OccupancyBand(inizio: "08:15", fine: nil).interval(on: day) == nil)
        #expect(OccupancyBand(inizio: nil, fine: "10:15").interval(on: day) == nil)
        #expect(OccupancyBand(inizio: "otto", fine: "dieci").interval(on: day) == nil)
    }

    /// A band that ends before it starts would otherwise produce a negative
    /// interval, which every reader of it treats as nonsense.
    @Test("Una fascia che finisce prima di iniziare non diventa negativa")
    func backwardsBand() throws {
        let interval = try #require(OccupancyBand(inizio: "16:00", fine: "14:00").interval(on: day))
        #expect(interval.end >= interval.start)
    }

    @Test("I secondi, quando ci sono, sono tenuti")
    func seconds() throws {
        let interval = try #require(OccupancyBand(inizio: "08:15:30", fine: "10:00:00").interval(on: day))
        #expect(PoliMiDate.romeCalendar.component(.second, from: interval.start) == 30)
    }
}

/// Answers occupancy requests with a body, keyed by the occupancy id in the
/// path, so tests running in parallel never read each other's answers. The
/// stub in `ConnectionProbeTests` answers with a status only, which is all a
/// probe looks at; decoding needs a body.
nonisolated final class OccupancyStub: URLProtocol, @unchecked Sendable {
    enum Answer: Sendable {
        case body(String, status: Int = 200)
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
        configuration.protocolClasses = [OccupancyStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // `…/ricerca/aula/occupazione/<id>/<giorno>`: the id is the second to
        // last component, and it is what the answer was registered under.
        let components = request.url?.pathComponents ?? []
        let id = components.count >= 2 ? components[components.count - 2] : ""
        let answer = Self.lock.withLock { Self.answers[id] }
        switch answer {
        case .body(let json, let status):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }
}

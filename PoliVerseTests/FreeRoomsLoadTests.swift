import Foundation
import Testing
@testable import PoliVerse

/// A campus pass in ``FreeRoomsModel`` meeting a change of campus or day.
///
/// The picker changes both while a pass runs, and the pass for the new choice
/// used to be turned away: the old one then published its rooms under the new
/// campus and stamped the load window with it.
@Suite("Aule libere: cambio di sede durante il caricamento", .tags(.network, .timing))
@MainActor
struct FreeRoomsLoadTests {
    /// A day that is not today, so no pass writes the widget's snapshot.
    private let day = PoliMiDate.time(12, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func room(_ id: String, campus: String, occupancy: String) -> Classroom {
        Classroom(id: id, capacity: 40, buildingCode: "B", floorCode: "0",
                  campusName: campus, occupancyID: occupancy)
    }

    @Test("Switching campus mid-pass shows the new campus, and the old pass does not overwrite it")
    func switchingCampusMidPass() async {
        let slow = "gate-\(UUID().uuidString)"
        let quick = "open-\(UUID().uuidString)"
        let arrived = GatedOccupancyStub.hold(slow)
        defer { GatedOccupancyStub.release(slow) }
        let model = FreeRoomsModel(
            catalogue: StubCatalogue([room("A1", campus: "Test A", occupancy: slow),
                                      room("B1", campus: "Test B", occupancy: quick)]),
            session: GatedOccupancyStub.session)
        model.day = day
        model.campus = "Test A"

        let first = Task { await model.load() }
        for await _ in arrived { break }

        model.campus = "Test B"
        await model.load()
        #expect(model.rooms.map(\.id) == ["B1"])

        GatedOccupancyStub.release(slow)
        await first.value
        #expect(model.rooms.map(\.id) == ["B1"])
        #expect(!model.isLoading)
    }

    @Test("The same campus asked twice mid-pass is fetched once")
    func sameCampusIsNotFetchedTwice() async {
        let slow = "gate-\(UUID().uuidString)"
        let arrived = GatedOccupancyStub.hold(slow)
        defer { GatedOccupancyStub.release(slow) }
        let model = FreeRoomsModel(
            catalogue: StubCatalogue([room("A1", campus: "Test A", occupancy: slow)]),
            session: GatedOccupancyStub.session)
        model.day = day
        model.campus = "Test A"

        let first = Task { await model.load() }
        for await _ in arrived { break }
        await model.load()
        #expect(model.isLoading)

        GatedOccupancyStub.release(slow)
        await first.value
        #expect(model.rooms.map(\.id) == ["A1"])
        #expect(GatedOccupancyStub.requests(for: slow) == 1)
    }
}

/// A fixed list of rooms.
@MainActor
private final class StubCatalogue: RoomCatalogue {
    let rooms: [Classroom]
    var campuses: [String] { Array(Set(rooms.compactMap(\.campusName))).sorted() }
    init(_ rooms: [Classroom]) { self.rooms = rooms }
    func load(force: Bool) async {}
}

/// Answers occupancy requests with no bookings, holding those whose id was
/// passed to ``hold(_:)`` until ``release(_:)``, so a test can act while a
/// pass is provably mid-flight. Keyed by occupancy id, so parallel tests never
/// share an answer.
nonisolated final class GatedOccupancyStub: URLProtocol, @unchecked Sendable {
    private struct Gate {
        let semaphore = DispatchSemaphore(value: 0)
        let arrival: AsyncStream<Void>.Continuation
        var released = false
    }

    nonisolated(unsafe) private static var gates: [String: Gate] = [:]
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    private static let lock = NSLock()

    /// Holds requests for an id, and yields once each one arrives.
    static func hold(_ id: String) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        lock.withLock { gates[id] = Gate(arrival: continuation) }
        return stream
    }

    /// Lets held requests for an id through; safe to call twice.
    static func release(_ id: String) {
        lock.withLock {
            guard var gate = gates[id], !gate.released else { return }
            gate.released = true
            gates[id] = gate
            // More than one waiter is possible; enough signals for all.
            for _ in 0..<8 { gate.semaphore.signal() }
        }
    }

    static func requests(for id: String) -> Int { lock.withLock { counts[id, default: 0] } }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatedOccupancyStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // `…/ricerca/aula/occupazione/<id>/<giorno>`.
        let components = request.url?.pathComponents ?? []
        let id = components.count >= 2 ? components[components.count - 2] : ""
        let gate = Self.lock.withLock { () -> Gate? in
            Self.counts[id, default: 0] += 1
            return Self.gates[id]
        }
        guard let gate, !gate.released else { return respond() }
        gate.arrival.yield()
        DispatchQueue.global().async {
            gate.semaphore.wait()
            self.respond()
        }
    }

    private func respond() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

import Foundation
import Testing
@testable import PoliVerse

@Suite("Free rooms snapshot")
struct FreeRoomsSnapshotTests {
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.startOfDay(for: .now)
            .addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private func snapshot(_ rooms: [FreeRoomsSnapshot.Room]) -> FreeRoomsSnapshot {
        FreeRoomsSnapshot(day: .now, campus: "Leonardo", rooms: rooms)
    }

    private func room(_ name: String, busy: [(Int, Int)]) -> FreeRoomsSnapshot.Room {
        FreeRoomsSnapshot.Room(
            id: name, name: name, building: nil, seats: nil,
            busy: busy.map { .init(start: at($0.0), end: at($0.1)) })
    }

    @Test("A room with nothing booked is free")
    func emptyRoomIsFree() {
        let free = snapshot([room("A", busy: [])]).free(at: at(10))
        #expect(free.map(\.name) == ["A"])
    }

    @Test("A booking covering the window hides the room")
    func bookedRoomIsNotFree() {
        let free = snapshot([room("A", busy: [(9, 11)])]).free(at: at(10))
        #expect(free.isEmpty)
    }

    @Test("A booking starting inside the half hour hides the room")
    func imminentBookingHides() {
        // 10:00 + 30 minutes overlaps a lecture starting at 10:15. The room is
        // empty at this instant and useless to sit down in, which is the whole
        // reason the question has a window rather than being a point in time.
        let free = snapshot([room("A", busy: [(10, 12)])]).free(at: at(9, 45))
        #expect(free.isEmpty)
    }

    @Test("A booking that ends exactly when the window opens leaves it free")
    func touchingBookingDoesNotHide() {
        let free = snapshot([room("A", busy: [(8, 10)])]).free(at: at(10))
        #expect(free.map(\.name) == ["A"])
    }

    @Test("A booking that starts exactly when the window closes leaves it free")
    func bookingAtWindowEndDoesNotHide() {
        let free = snapshot([room("A", busy: [(10, 12)])]).free(at: at(9, 30))
        #expect(free.map(\.name) == ["A"])
    }

    @Test("Results are ordered by name")
    func ordered() {
        let free = snapshot([room("C", busy: []), room("A", busy: []), room("B", busy: [])])
            .free(at: at(10))
        #expect(free.map(\.name) == ["A", "B", "C"])
    }

    @Test("A snapshot from another day does not describe today")
    func staleDay() {
        var yesterday = snapshot([])
        yesterday.day = .now.addingTimeInterval(-86400)
        #expect(yesterday.covers(.now) == false)
        #expect(snapshot([]).covers(.now))
    }

    @Test("Round-trips through the cache")
    func codable() throws {
        let original = snapshot([room("A", busy: [(9, 11)])])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(FreeRoomsSnapshot.self, from: data) == original)
    }
}

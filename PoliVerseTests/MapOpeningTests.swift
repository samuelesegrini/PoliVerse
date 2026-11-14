import Foundation
import Testing
@testable import PoliVerse

@Suite("Apertura della nuova mappa")
struct MapOpeningTests {
    private let rooms: [MapFreeSummary.Room] = [
        .init(id: "3.1.2", campus: "Leonardo", building: "B3"),
        .init(id: "4.0.1", campus: "Leonardo", building: "B4"),
        .init(id: "11.0.1", campus: "Leonardo", building: "B11"),
        .init(id: "BL.27.1", campus: "Bovisa", building: "BL27"),
    ]

    @Test func countsOnlyTheCampusChosen() {
        #expect(MapFreeSummary.make(free: rooms, campus: "Leonardo", origin: nil, metres: [:]).count == 3)
        #expect(MapFreeSummary.make(free: rooms, campus: "Bovisa", origin: nil, metres: [:]).count == 1)
        #expect(MapFreeSummary.make(free: rooms, campus: nil, origin: nil, metres: [:]).count == 4)
        #expect(MapFreeSummary.make(free: rooms, campus: "Como", origin: nil, metres: [:])
                == .init(count: 0, nearest: nil))
    }

    @Test func nearestIsInTheOriginThenTheClosestBuilding() {
        let metres = ["B4": 120, "B11": 60.0]
        #expect(MapFreeSummary.make(free: rooms, campus: "Leonardo", origin: "B3", metres: metres).nearest == "3.1.2")
        #expect(MapFreeSummary.make(free: rooms, campus: "Leonardo", origin: "B9", metres: metres).nearest == "11.0.1")
        // Never a room on another campus, however close.
        #expect(MapFreeSummary.make(free: rooms, campus: "Bovisa", origin: "B3", metres: metres).nearest == "BL.27.1")
    }

    @Test func theNearestCarriesWhenItStopsBeingFree() {
        let at4 = Date(timeIntervalSince1970: 1_800_000_000)
        let free = [MapFreeSummary.Room(id: "3.0.1", campus: "Leonardo", building: "B3", until: at4),
                    MapFreeSummary.Room(id: "4.0.1", campus: "Leonardo", building: "B4")]
        #expect(MapFreeSummary.make(free: free, campus: nil, origin: "B3", metres: [:]).until == at4)
        #expect(MapFreeSummary.make(free: free, campus: nil, origin: "B4", metres: [:]).until == nil)
    }

    @Test func withoutDistancesTheCodeDecides() {
        #expect(MapFreeSummary.make(free: rooms, campus: "Leonardo", origin: nil, metres: [:]).nearest == "3.1.2")
    }

    @Test func walkingMinutesRoundUpAndNeverZero() {
        #expect(MapWalk.minutes(metres: 0) == 1)
        #expect(MapWalk.minutes(metres: 240) == 4)
        #expect(MapWalk.minutes(metres: 250) == 5)
    }

    private func recent(_ id: String, _ kind: MapRecent.Kind = .room) -> MapRecent {
        MapRecent(kind: kind, id: id, floor: nil, title: id, detail: nil)
    }

    @Test func recentsPutTheLatestFirstWithoutCopies() {
        var list: [MapRecent] = []
        for id in ["a", "b", "c", "b"] { list = MapRecents.adding(recent(id), to: list) }
        #expect(list.map(\.id) == ["b", "c", "a"])
        // A building and a room with the same code are different things.
        list = MapRecents.adding(recent("a", .building), to: list)
        #expect(list.count == 4)
    }

    @Test func recentsKeepAtMostFive() {
        var list: [MapRecent] = []
        for id in ["1", "2", "3", "4", "5", "6", "7"] { list = MapRecents.adding(recent(id), to: list) }
        #expect(list.map(\.id) == ["7", "6", "5", "4", "3"])
    }

    @Test func recentsSurviveTheDefaults() {
        let list = [recent("3.1.2"), MapRecent(kind: .building, id: "MIA0203", floor: nil, title: "Edificio 3", detail: "Leonardo")]
        #expect(MapRecents.decode(MapRecents.encode(list)) == list)
        #expect(MapRecents.decode("") == [])
        #expect(MapRecents.decode("not json") == [])
    }
}

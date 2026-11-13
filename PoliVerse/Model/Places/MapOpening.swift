import Foundation

// What the new map's opening sheet (``BetaFeature/newMap``) says before anything is touched:
// how many rooms are free on the campus chosen and the nearest, how far the next lesson is,
// and what was searched last.

/// How many rooms are free on a campus, and the nearest of them.
nonisolated enum MapFreeSummary {
    /// A free room, with where it is.
    struct Room: Sendable, Equatable {
        /// The room's code, as the catalogue and the bookings share it.
        let id: String
        /// The campus it is on, where the catalogue says.
        let campus: String?
        /// Its building's code.
        let building: String
        /// When it stops being free today; `nil` when it stays free.
        var until: Date? = nil
    }

    /// What the opening sheet writes.
    struct Summary: Sendable, Equatable {
        /// How many rooms are free on the campus.
        let count: Int
        /// The nearest free room's code, `nil` when none is free.
        let nearest: String?
        /// When the nearest stops being free; `nil` when it stays free all day.
        var until: Date? = nil
    }

    /// Counts the free rooms on one campus and picks the nearest.
    ///
    /// - Parameters:
    ///   - free: The rooms free now.
    ///   - campus: The campus chosen; `nil` counts them all.
    ///   - origin: The building the student is in or going to: its rooms come first.
    ///   - metres: How far each building is from the origin, where known. A building with no
    ///     distance comes after every one with a distance.
    /// - Returns: The count and the nearest room, ties broken by the room's code.
    static func make(free: [Room], campus: String?, origin: String?, metres: [String: Double]) -> Summary {
        let here = free.filter { campus == nil || $0.campus == campus }
        func rank(_ room: Room) -> Double {
            if room.building == origin { return -1 }
            return metres[room.building] ?? .infinity
        }
        let nearest = here.min { left, right in
            let a = rank(left), b = rank(right)
            if a != b { return a < b }
            return left.id.localizedStandardCompare(right.id) == .orderedAscending
        }
        return Summary(count: here.count, nearest: nearest?.id, until: nearest?.until)
    }
}

/// How long a walk between two buildings takes.
nonisolated enum MapWalk {
    /// Metres a minute, at an unhurried pace between lessons.
    static let metresPerMinute = 80.0
    /// How much longer the path is than the straight line, round corners and courtyards.
    static let detour = 1.3

    /// The minutes to walk a straight-line distance, at least one.
    ///
    /// - Parameter metres: The straight-line distance.
    /// - Returns: Whole minutes, rounded up.
    static func minutes(metres: Double) -> Int {
        max(1, Int((metres * detour / metresPerMinute).rounded(.up)))
    }
}

/// Something opened from the map's search, to offer again.
nonisolated struct MapRecent: Codable, Sendable, Equatable, Identifiable {
    /// A room or a building.
    enum Kind: String, Codable, Sendable { case room, building }

    /// What it is.
    let kind: Kind
    /// The room's space code, or the building's code.
    let id: String
    /// The floor's code, for a room.
    let floor: String?
    /// What is shown in bold: "3.1.2", "Edificio 3".
    let title: String
    /// Where it is.
    let detail: String?
}

/// The recent searches, most recent first.
nonisolated enum MapRecents {
    /// How many are kept.
    static let cap = 5

    /// The list with one more opened.
    ///
    /// - Parameters:
    ///   - item: What was opened.
    ///   - list: The list so far, most recent first.
    /// - Returns: The item first, any earlier copy of it removed, at most ``cap`` long.
    static func adding(_ item: MapRecent, to list: [MapRecent]) -> [MapRecent] {
        Array(([item] + list.filter { $0.id != item.id || $0.kind != item.kind }).prefix(cap))
    }

    /// The list stored as text, for the defaults.
    static func encode(_ list: [MapRecent]) -> String {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The list read back from text; empty when there is none or it cannot be read.
    static func decode(_ text: String) -> [MapRecent] {
        guard let data = text.data(using: .utf8), !text.isEmpty else { return [] }
        return (try? JSONDecoder().decode([MapRecent].self, from: data)) ?? []
    }
}

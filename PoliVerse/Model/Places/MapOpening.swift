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

/// The lesson card at the top of the new map's opening sheet: the lesson in progress with the
/// one after it, or else the next lesson today.
nonisolated enum MapLessonCard {
    /// What the card shows.
    struct Lessons: Equatable, Sendable {
        /// The lesson in progress, if any.
        let current: AgendaEvent?
        /// The lesson after it today, or the next one today when none is in progress.
        let next: AgendaEvent?
    }

    /// Picks the lessons for the card: lectures and exams of today that have not ended.
    ///
    /// - Parameters:
    ///   - events: The agenda.
    ///   - now: Now.
    ///   - calendar: The calendar that says what today is.
    /// - Returns: The lesson in progress and the next to start; `nil` with neither.
    static func pick(_ events: [AgendaEvent], now: Date,
                     calendar: Calendar = PoliMiDate.romeCalendar) -> Lessons? {
        let today = events
            .filter { [.lecture, .exam].contains($0.kind) && calendar.isDate($0.start, inSameDayAs: now) && $0.end > now }
            .sorted { $0.start < $1.start }
        let current = today.first { $0.isOngoing(at: now) }
        let next = today.first { $0.start > now && $0.id != current?.id }
        guard current != nil || next != nil else { return nil }
        return Lessons(current: current, next: next)
    }

    /// How much of a lesson has gone, 0…1.
    static func progress(start: Date, end: Date, now: Date) -> Double {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / length, 0), 1)
    }

    /// "termina tra 40 min", "termina tra 1 h 5 min".
    static func endsIn(from now: Date, to end: Date) -> String {
        let minutes = max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 { return String(localized: "termina tra \(minutes) min") }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String(localized: "termina tra \(hours) h")
            : String(localized: "termina tra \(hours) h \(rest) min")
    }

    /// Where the walk to a lesson starts: the lesson in progress, else the last one today that
    /// ended before it.
    ///
    /// - Parameters:
    ///   - target: The lesson walked to.
    ///   - events: Today's lessons.
    ///   - now: Now.
    static func walkStart(to target: AgendaEvent, in events: [AgendaEvent], now: Date) -> AgendaEvent? {
        let lessons = events.filter { [.lecture, .exam].contains($0.kind) && $0.id != target.id }
        if let current = lessons.first(where: { $0.isOngoing(at: now) && $0.end <= target.start }) { return current }
        return lessons.filter { $0.end <= target.start }.max { $0.end < $1.end }
    }
}

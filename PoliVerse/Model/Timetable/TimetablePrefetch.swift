import Foundation

/// Something to prepare before a lecture.
nonisolated enum PrefetchItem: Hashable, Sendable {
    /// A room: its bookings for the day, its floor plan and its equipment. The
    /// names are those the timetable gives it, as ``AgendaEvent/roomAcronym`` and
    /// ``AgendaEvent/room``.
    case room(names: [String], day: Date)
    /// A course's page on WeBeep, found by the lecture's title.
    case course(title: String)

    /// How many requests preparing it takes at most: the bookings, the plan and
    /// the two equipment calls for a room, one page for a course.
    var cost: Int {
        switch self {
        case .room: 4
        case .course: 1
        }
    }
}

/// What to prepare from the timetable: what the lectures starting soon need.
///
/// Values in, list out. The timetable says where the student will be in the next
/// hour, which is the one prediction the app can make without guessing at habits
/// (assumption D5): the room they are walking to and the course it belongs to.
/// The building's 3D model is not on the list: it ships with the app.
nonisolated enum TimetablePrefetch {
    /// How far ahead a lecture is prepared for.
    static let lead: TimeInterval = 3600

    /// The things the lectures starting within `lead` of `now` need, soonest
    /// lecture first, each once.
    ///
    /// - Parameters:
    ///   - now: The current moment.
    ///   - lectures: The timetable's entries; only lectures count.
    ///   - lead: How far ahead to look.
    static func wanted(now: Date, lectures: [AgendaEvent], lead: TimeInterval = lead) -> [PrefetchItem] {
        let soon = lectures
            .filter { $0.kind == .lecture && $0.start > now && $0.start.timeIntervalSince(now) <= lead }
            .sorted { $0.start < $1.start }
        var items: [PrefetchItem] = []
        var seen: Set<PrefetchItem> = []
        for lecture in soon {
            let names = [lecture.roomAcronym, lecture.room].compactMap { $0 }.filter { !$0.isEmpty }
            let day = PoliMiDate.romeCalendar.startOfDay(for: lecture.start)
            var wanted: [PrefetchItem] = []
            if !names.isEmpty { wanted.append(.room(names: names, day: day)) }
            if !lecture.title.isEmpty { wanted.append(.course(title: lecture.title)) }
            for item in wanted where seen.insert(item).inserted { items.append(item) }
        }
        return items
    }

    /// The items that fit in an allowance of requests, in order: an item that
    /// does not fit is left out, and the smaller ones after it still go.
    ///
    /// - Parameters:
    ///   - items: The wanted items, most urgent first.
    ///   - allowance: How many requests may go out.
    static func fitting(_ items: [PrefetchItem], allowance: Int) -> [PrefetchItem] {
        var left = allowance
        return items.filter { item in
            guard item.cost <= left else { return false }
            left -= item.cost
            return true
        }
    }
}

import Foundation

/// What kind of entry an agenda item is. Values match the upstream
/// `event_type.typeId` and must not be renumbered.
nonisolated enum EventKind: Int, Sendable, CaseIterable {
    case lecture = 1
    case exam = 2
    case news = 3
    case deadline = 4
    case custom = 5

    var label: String {
        switch self {
        case .lecture: "Lezione"
        case .exam: "Esame"
        case .news: "Avviso"
        case .deadline: "Scadenza"
        case .custom: "Personale"
        }
    }

    var icon: String {
        switch self {
        case .lecture: "person.bubble"
        case .exam: "pencil.and.list.clipboard"
        case .news: "megaphone"
        case .deadline: "exclamationmark.circle"
        case .custom: "star"
        }
    }
}

/// One entry in the student's agenda.
nonisolated struct AgendaEvent: Identifiable, Sendable, Hashable {
    let id: Int
    let title: String
    let start: Date
    let end: Date
    let kind: EventKind
    /// Full room name, e.g. "Aula Rogers".
    let room: String?
    /// Short form shown in tight layouts, e.g. "R.0.1".
    let roomAcronym: String?
    let calendarName: String?

    /// Enforces `end >= start`.
    ///
    /// Anything that forms `start...end` traps when the range is inverted, and
    /// zero-length entries are legitimate here — a deadline is an instant, not
    /// an interval. Clamping in the initialiser means no call site can build an
    /// event that crashes a view later, which is exactly how this bit first
    /// (a mock deadline written as 23:15 → 23:00 took down the calendar tab).
    init(
        id: Int,
        title: String,
        start: Date,
        end: Date,
        kind: EventKind,
        room: String? = nil,
        roomAcronym: String? = nil,
        calendarName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = Swift.max(end, start)
        self.kind = kind
        self.room = room
        self.roomAcronym = roomAcronym
        self.calendarName = calendarName
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// True while the event is happening, used to highlight "now" in the list.
    ///
    /// Instantaneous events (a deadline) are never "ongoing" — a zero-width
    /// range would only match the exact second.
    func isOngoing(at moment: Date = .now) -> Bool {
        guard end > start else { return false }
        return (start...end).contains(moment)
    }
}

// MARK: - Wire types

/// Most agenda strings arrive as an `{ it, en }` pair.
nonisolated struct LocalizedText: Decodable, Sendable {
    let it: String?
    let en: String?

    /// Prefers Italian, since the rest of the UI is Italian, but falls back
    /// rather than showing an empty row.
    var preferred: String { it ?? en ?? "" }
}

nonisolated struct AgendaEventDTO: Decodable, Sendable {
    struct EventTypeDTO: Decodable, Sendable {
        let typeId: Int?
        let type_dn: LocalizedText?
    }

    struct RoomDTO: Decodable, Sendable {
        let room_dn: String?
        let acronym_dn: String?
    }

    struct CalendarDTO: Decodable, Sendable {
        let calendar_dn: LocalizedText?
    }

    let event_id: Int?
    let date_start: String?
    let date_end: String?
    let title: LocalizedText?
    let event_type: EventTypeDTO?
    let room: RoomDTO?
    let calendar: CalendarDTO?

    func toEvent() -> AgendaEvent? {
        // An event we cannot place in time is worse than no event at all.
        // Everything else degrades; only the timestamps are load-bearing.
        guard
            let date_start, let date_end,
            let start = PoliMiDate.parse(date_start),
            let end = PoliMiDate.parse(date_end)
        else { return nil }

        return AgendaEvent(
            id: event_id ?? abs(date_start.hashValue),
            title: title?.preferred.isEmpty == false ? title!.preferred : "Evento",
            start: start,
            end: end,
            kind: EventKind(rawValue: event_type?.typeId ?? -1) ?? .custom,
            room: room?.room_dn,
            roomAcronym: room?.acronym_dn,
            calendarName: calendar?.calendar_dn?.preferred
        )
    }
}

/// Timestamp handling for the agenda endpoint.
///
/// - Important: `date_start` / `date_end` have **no timezone designator** —
///   they look like `2026-03-14T09:15:00`. They are Politecnico wall-clock
///   time, i.e. Europe/Rome. Feeding them to `.iso8601` throws, and treating
///   them as UTC silently shifts every lecture by one or two hours depending
///   on daylight saving. Both failure modes are easy to ship by accident, so
///   the zone is pinned here explicitly.
nonisolated enum PoliMiDate {
    /// Wall-clock, the documented shape.
    private static let wallClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    /// Date-only, seen on all-day entries.
    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let date = wallClock.date(from: trimmed) { return date }
        // Tolerated in case the backend ever starts sending a real offset.
        // `ISO8601FormatStyle` is Sendable; `ISO8601DateFormatter` is not.
        if let date = try? Date(trimmed, strategy: .iso8601) { return date }
        if let date = dateOnly.date(from: trimmed) { return date }
        return nil
    }

    /// Combines an `HH:mm` (or `HH:mm:ss`) string with an existing date.
    ///
    /// The exams endpoint splits a sitting into `d_app` (the day) and `ora_ok`
    /// (the time) instead of sending one timestamp.
    static func applying(time: String, to date: Date) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return romeCalendar.date(
            bySettingHour: parts[0],
            minute: parts[1],
            second: parts.count > 2 ? parts[2] : 0,
            of: date
        )
    }

    /// The `start_date` query parameter wants a bare `yyyy-MM-dd`.
    static func queryString(_ date: Date) -> String { dateOnly.string(from: date) }

    /// Rome, for grouping events into days. Using the device calendar would
    /// put a 00:30 lecture on the wrong day for a student travelling.
    static var romeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        // Building a Calendar by identifier rather than from a locale gives
        // firstWeekday = 1 (Sunday). Italian weeks start on Monday, and the
        // week strip is derived from this, so set it explicitly.
        calendar.firstWeekday = 2
        return calendar
    }
}

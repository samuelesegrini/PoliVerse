import Foundation

/// What kind of entry an agenda item is.
///
/// - Important: The raw values match the upstream `event_type.typeId` and must not
///   be renumbered.
nonisolated enum EventKind: Int, Sendable, CaseIterable, Codable {
    /// A timetabled lecture, laboratory or tutorial.
    case lecture = 1
    /// An exam sitting.
    case exam = 2
    /// A notice the agenda carries as an entry.
    case news = 3
    /// A deadline, which is an instant rather than an interval.
    case deadline = 4
    /// A personal entry, and the fallback for a `typeId` this app does not know.
    case custom = 5

    /// The kind's name as it appears on screen.
    var label: String {
        switch self {
        case .lecture: "Lezione"
        case .exam: "Esame"
        case .news: "Avviso"
        case .deadline: "Scadenza"
        case .custom: "Personale"
        }
    }

    /// The SF Symbol name for the kind.
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
///
/// Both initialisers clamp ``end`` to be no earlier than ``start``, so no value of
/// this type can form an inverted range for a view to trap on. Zero-length entries
/// are legitimate — a deadline is an instant — and ``isOngoing(at:)`` accounts for
/// them.
///
/// Written into the app group by ``TimetablePublishing`` for the widgets to read.
nonisolated struct AgendaEvent: Identifiable, Sendable, Hashable, Codable {
    /// The upstream `event_id`, or a hash of the start timestamp when the payload
    /// omits it.
    let id: Int
    /// The entry's name on screen.
    let title: String
    /// When the entry begins, as an absolute date resolved from Rome wall clock.
    let start: Date
    /// When the entry ends. Never earlier than ``start``.
    let end: Date
    /// What kind of entry this is.
    let kind: EventKind
    /// The room as the timetable names it, for example `"Aula Rogers"` — or, for
    /// the rooms that have no name, the ateneo's own internal code, `"005A"`.
    let room: String?
    /// The code on the door: building, floor, room, for example `"5.1.1"`.
    ///
    /// Not merely a short form of ``room``. This is the code the Politecnico
    /// signposts, times and speaks in, and the only one of the two a student
    /// can act on: `"005A"` names the same room but appears nowhere they will
    /// ever stand. See ``roomLabel``.
    let roomAcronym: String?
    /// The upstream calendar the entry came from.
    let calendarName: String?
    /// Free text the agenda attaches to some entries.
    var details: String?
    /// Teaching form — lecture, laboratory, tutorial — keyed upstream as
    /// `LBL_FORMA_DIDATTICA_*`.
    var subtype: String?
    /// Labels the agenda attaches, used upstream to choose card artwork.
    var tags: [String] = []

    /// Decodes an entry through ``init(id:title:start:end:kind:room:roomAcronym:calendarName:details:subtype:tags:)``,
    /// so the clamp on ``end`` applies to cached files as well as to fresh payloads.
    ///
    /// A synthesised `Codable` would assign the stored `end` directly, letting a file
    /// written by another version reintroduce an inverted range.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: A decoding error when `id`, `title`, `start`, `end` or `kind` is
    ///   missing or malformed. Every other key is optional.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(Int.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            start: try container.decode(Date.self, forKey: .start),
            end: try container.decode(Date.self, forKey: .end),
            kind: try container.decode(EventKind.self, forKey: .kind),
            room: try container.decodeIfPresent(String.self, forKey: .room),
            roomAcronym: try container.decodeIfPresent(String.self, forKey: .roomAcronym),
            calendarName: try container.decodeIfPresent(String.self, forKey: .calendarName),
            details: try container.decodeIfPresent(String.self, forKey: .details),
            subtype: try container.decodeIfPresent(String.self, forKey: .subtype),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
    }

    /// Creates an entry, clamping ``end`` to be no earlier than ``start``.
    ///
    /// - Parameters:
    ///   - id: The entry's identifier.
    ///   - title: The entry's name on screen.
    ///   - start: When it begins.
    ///   - end: When it ends. Raised to `start` when it precedes it.
    ///   - kind: What kind of entry it is.
    ///   - room: Full room name.
    ///   - roomAcronym: Short room form.
    ///   - calendarName: The upstream calendar it came from.
    ///   - details: Free text.
    ///   - subtype: Teaching form.
    ///   - tags: Labels the agenda attaches.
    init(
        id: Int,
        title: String,
        start: Date,
        end: Date,
        kind: EventKind,
        room: String? = nil,
        roomAcronym: String? = nil,
        calendarName: String? = nil,
        details: String? = nil,
        subtype: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = Swift.max(end, start)
        self.kind = kind
        self.room = room
        self.roomAcronym = roomAcronym
        self.calendarName = calendarName
        self.details = details
        self.subtype = subtype
        self.tags = tags
    }

    /// How long the entry lasts, in seconds. Zero for an instantaneous entry.
    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Whether the entry is happening at a given moment, which the list uses to mark
    /// “now”.
    ///
    /// - Parameter moment: The moment to test.
    /// - Returns: `true` when the moment falls in `start...end`. Always `false` for an
    ///   instantaneous entry, whose zero-width range would match only one second.
    func isOngoing(at moment: Date = .now) -> Bool {
        guard end > start else { return false }
        return (start...end).contains(moment)
    }

    /// Where to go, in the words the Politecnico actually uses.
    ///
    /// Neither field is reliably the one to show. ``room`` is whatever the
    /// timetable recorded: sometimes a hall everyone knows by name — Rogers,
    /// De Donato, Castigliano — and sometimes `"005A"`, the ateneo's internal
    /// code, which is printed on no door and spoken by nobody. ``roomAcronym``
    /// is the signposted code, building, floor and room: `"5.1.1"`.
    ///
    /// So the choice is not between the two fields but between two kinds of
    /// answer. Where the hall has a name, the name is what a student will be
    /// told and what they will ask for, and the code adds nothing. Where it
    /// does not, the code is the only thing that will get them there, and
    /// `"005A"` is worse than useless — it looks like an answer.
    ///
    /// See ``RoomNaming`` for how the two are told apart.
    var roomLabel: String? {
        if let room, RoomNaming.isName(room) { return room }
        return roomAcronym ?? room
    }

    /// The door code, when it is worth showing beside ``roomLabel``.
    ///
    /// `nil` when the label already is the code, so that a caption showing
    /// both does not print `"5.1.1 · 5.1.1"`. Named halls keep it: someone who
    /// has never been to De Donato still needs the building.
    var roomCode: String? {
        guard let roomAcronym, roomAcronym != roomLabel else { return nil }
        return roomAcronym
    }
}

/// Telling a room's name apart from a room's code.
///
/// The timetable writes both into the same field, and nothing in the payload
/// says which one arrived. What separates them is what they are made of: halls
/// are named after people and places — Rogers, De Donato, Magna — while codes
/// are numbered. Strip the word that says what kind of room it is, and a digit
/// in what remains means a code.
///
/// This is a heuristic, and it is the right kind of heuristic: it is wrong only
/// about halls with a number in their name, and being wrong there costs a
/// student the name and hands them the door code, which still gets them to the
/// room.
nonisolated enum RoomNaming {
    /// The words a room label may already begin with, lowercased.
    ///
    /// Used only to decide whether to say "Aula" in front of it again. Longest
    /// first, so that `"laboratorio"` is stripped as itself rather than leaving
    /// `"oratorio"` behind from `"lab"`.
    private static let kinds = ["laboratorio", "teatro", "aula", "sala", "lab"]

    /// The subset of ``kinds`` that says what kind of room it is and nothing
    /// more.
    ///
    /// `"Teatro"` is missing on purpose: it is not a kind of room the way
    /// `"Aula"` is, it is a place, and a hall called nothing but Teatro is
    /// named. `"Aula"` on its own names nothing — it is the word for any of
    /// them — so it is the door code that has something to say.
    private static let generics = ["laboratorio", "aula", "sala", "lab"]

    /// Whether a label already says what kind of room it is.
    ///
    /// - Parameter label: The room as the timetable spelled it.
    /// - Returns: `true` when it begins with a word like `"Aula"`.
    static func namesKind(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return kinds.contains { lowered.hasPrefix($0) }
    }

    /// Whether a label is a name someone would use, rather than a code.
    ///
    /// - Parameter label: The room as the timetable spelled it.
    /// - Returns: `true` for `"Aula Rogers"`, `false` for `"005A"` or `"Aula 3"`.
    static func isName(_ label: String) -> Bool {
        var bare = label.lowercased().trimmingCharacters(in: .whitespaces)
        guard !bare.isEmpty else { return false }
        for kind in generics where bare.hasPrefix(kind) {
            bare = String(bare.dropFirst(kind.count)).trimmingCharacters(in: .whitespaces)
            // Nothing after the generic word: "Aula" names no particular room.
            guard !bare.isEmpty else { return false }
            break
        }
        return !bare.contains(where: \.isNumber)
    }

    /// A room with the generic word taken off, for a field already labelled
    /// with it.
    ///
    /// A row headed "Aula" whose value is `"Aula Magna"` reads "Aula: Aula
    /// Magna". The word belongs to the heading there, not to the value, so the
    /// value gives up its copy — `"Aula Magna"` becomes `"Magna"`, which is how
    /// the hall is spoken of anyway.
    ///
    /// Only the generic words go. `"Teatro"` is the room's name, not a heading
    /// repeated, and stripping it would leave nothing at all.
    ///
    /// - Parameter label: The room as the timetable spelled it.
    /// - Returns: The value to put under an "Aula" heading.
    static func bare(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        let lowered = trimmed.lowercased()
        for kind in generics where lowered.hasPrefix(kind) {
            let rest = String(trimmed.dropFirst(kind.count)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? trimmed : rest
        }
        return trimmed
    }

    /// A room worded for a sentence: `"Aula 5.1.1"`, `"Aula Rogers"`.
    ///
    /// The word is added, not assumed — the timetable's own names already carry
    /// it, and prefixing again reads `"Aula Aula Rogers"`.
    ///
    /// - Parameter label: The room to word.
    /// - Returns: The phrase to put in a sentence.
    static func sentence(_ label: String) -> String {
        namesKind(label) ? label : "Aula \(label)"
    }
}

// MARK: - Wire types

/// An `{ it, en }` pair, the shape most agenda strings arrive in.
nonisolated struct LocalizedText: Decodable, Sendable {
    /// The Italian text, when present.
    let it: String?
    /// The English text, when present.
    let en: String?

    /// The Italian text, falling back to the English and then to the empty string, so
    /// a partly populated pair does not render an empty row.
    var preferred: String { it ?? en ?? "" }
}

/// One agenda entry as the timetable endpoint sends it.
///
/// Every field is optional, and ``toEvent()`` decides what is load-bearing.
nonisolated struct AgendaEventDTO: Decodable, Sendable {
    /// The upstream event type, whose `typeId` maps to ``EventKind``.
    struct EventTypeDTO: Decodable, Sendable {
        /// The numeric kind, matched against ``EventKind``.
        let typeId: Int?
        /// The kind's upstream display name. Not used; ``EventKind/label`` is shown.
        let type_dn: LocalizedText?
    }

    /// The room an entry is held in.
    struct RoomDTO: Decodable, Sendable {
        /// Full room name.
        let room_dn: String?
        /// Short room form.
        let acronym_dn: String?
    }

    /// The upstream calendar an entry belongs to.
    struct CalendarDTO: Decodable, Sendable {
        /// The calendar's display name.
        let calendar_dn: LocalizedText?
    }

    /// One label the agenda attaches to an entry.
    struct TagDTO: Decodable, Sendable {
        /// The label's upstream identifier.
        let event_tag_id: Int?
        /// The label's text.
        let denomination: LocalizedText?
    }

    /// The entry's upstream identifier.
    let event_id: Int?
    /// Start timestamp, Rome wall clock without a zone designator.
    let date_start: String?
    /// End timestamp, Rome wall clock without a zone designator.
    let date_end: String?
    /// The entry's name.
    let title: LocalizedText?
    /// The entry's kind.
    let event_type: EventTypeDTO?
    /// Where the entry is held.
    let room: RoomDTO?
    /// Which upstream calendar the entry came from.
    let calendar: CalendarDTO?
    /// Free text attached to the entry.
    let description: LocalizedText?
    /// Teaching form key.
    let event_subtype: String?
    /// Labels attached to the entry.
    let tags: [TagDTO]?

    /// Converts the payload into an ``AgendaEvent``.
    ///
    /// Only the timestamps are load-bearing: everything else degrades to a default —
    /// an unknown kind becomes ``EventKind/custom``, a missing title becomes
    /// `"Evento"`, a missing id becomes a hash of the start timestamp.
    ///
    /// - Returns: The entry, or `nil` when either timestamp is missing or unparseable,
    ///   since an entry that cannot be placed in time is worse than no entry.
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
            calendarName: calendar?.calendar_dn?.preferred,
            details: description?.preferred.isEmpty == false ? description?.preferred : nil,
            subtype: event_subtype,
            tags: (tags ?? []).compactMap {
                let name = $0.denomination?.preferred
                return name?.isEmpty == false ? name : nil
            }
        )
    }
}

/// Date and time handling for the Politecnico's endpoints.
///
/// - Important: `date_start` and `date_end` carry no timezone designator — they
///   look like `2026-03-14T09:15:00` — and are Rome wall clock. Parsing them as
///   ISO 8601 throws, and treating them as UTC shifts every lecture by one or two
///   hours depending on daylight saving, so the zone is pinned explicitly
///   throughout this type.
nonisolated enum PoliMiDate {
    /// `yyyy-MM-dd'T'HH:mm:ss` in Europe/Rome, the documented shape.
    private static let wallClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    /// `yyyy-MM-dd` in Europe/Rome, seen on all-day entries and used for query
    /// parameters.
    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Parses a timestamp from any of the three shapes these endpoints produce.
    ///
    /// Tried in order: Rome wall clock, ISO 8601 with a real offset, then date-only.
    ///
    /// - Parameter raw: The timestamp, with surrounding whitespace tolerated.
    /// - Returns: The absolute date, or `nil` when no shape matches.
    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let date = wallClock.date(from: trimmed) { return date }
        // Tolerated in case the backend ever starts sending a real offset.
        // `ISO8601FormatStyle` is Sendable; `ISO8601DateFormatter` is not.
        if let date = try? Date(trimmed, strategy: .iso8601) { return date }
        if let date = dateOnly.date(from: trimmed) { return date }
        return nil
    }

    /// A given time of day on the same Rome calendar day as a date.
    ///
    /// Computed by adding components to the start of the day rather than with
    /// `Calendar.date(bySettingHour:of:)`, which searches forward for the next match
    /// and so would return tomorrow when asked for a time already past.
    ///
    /// - Parameters:
    ///   - hour: Hour of the day.
    ///   - minute: Minute of the hour.
    ///   - day: The day to resolve against.
    /// - Returns: The resolved date, or `day` unchanged if it cannot be formed.
    static func time(_ hour: Int, _ minute: Int = 0, on day: Date) -> Date {
        let calendar = romeCalendar
        let start = calendar.startOfDay(for: day)
        return calendar.date(
            byAdding: DateComponents(hour: hour, minute: minute), to: start) ?? day
    }

    /// Combines an `HH:mm` or `HH:mm:ss` string with an existing date, in Rome.
    ///
    /// The exams endpoint splits a sitting into a day and a time rather than sending
    /// one timestamp.
    ///
    /// - Parameters:
    ///   - time: The time of day, colon separated.
    ///   - date: The day to resolve against.
    /// - Returns: The resolved date, or `nil` when fewer than two components parse.
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

    /// The academic year an exam sitting belongs to, as `"2025/26"`.
    ///
    /// A sitting's year turns in October: the autumn session closes the year whose
    /// teaching it examines rather than opening the next one. Filing a September
    /// sitting under the new year would point it at a different edition of the
    /// manifesto and record it under the wrong year in the libretto.
    ///
    /// This differs from ``Course/academicYearLabel(for:)``, which answers which year a
    /// *teaching* belongs to and so turns in September.
    ///
    /// - Parameters:
    ///   - date: When the sitting is held.
    ///   - calendar: The calendar to read the month from.
    /// - Returns: The label, or `nil` when the date yields no year and month.
    static func academicYear(ofSitting date: Date,
                             calendar: Calendar = PoliMiDate.romeCalendar) -> String? {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return nil }
        let start = month >= 10 ? year : year - 1
        return "\(start)/\(String(format: "%02d", (start + 1) % 100))"
    }

    /// A date as the bare `yyyy-MM-dd` these endpoints' query parameters want.
    ///
    /// - Parameter date: The date to format.
    /// - Returns: The formatted day, in Rome.
    static func queryString(_ date: Date) -> String { dateOnly.string(from: date) }

    /// A Gregorian calendar in Europe/Rome whose weeks start on Monday.
    ///
    /// Events are grouped into days with this rather than with the device calendar,
    /// which would put a late-evening lecture on the wrong day for a travelling
    /// student. `firstWeekday` is set explicitly because a calendar built by identifier
    /// starts its weeks on Sunday, and the week strip is derived from it.
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

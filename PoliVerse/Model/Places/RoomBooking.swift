import Foundation

/// A campus, as the bookings service names them.
///
/// Distinct from the maps service's campuses: the two backends name the same places
/// differently, so the bookings service's own list is used when talking to it.
nonisolated struct AuleSite: Identifiable, Sendable, Hashable {
    /// The site's identifier, falling back to its name when the payload has no id.
    let id: String
    /// The site's name, falling back to its identifier.
    let name: String

    /// Reads a site out of a decoded payload, trying several candidate key spellings.
    ///
    /// - Parameters:
    ///   - fields: One site's fields.
    ///   - index: The site's position in the payload.
    /// - Returns: `nil` when neither an identifier nor a name can be found.
    init?(fields: [String: JSONValue], index: Int) {
        let rawID = fields.firstValue([
            "id_sede", "idSede", "sede", "id", "codice", "cod_sede", "csi_sede",
        ])?.stringValue
        let name = fields.firstValue([
            "nome", "descrizione", "denominazione", "name", "sede_desc",
            "descrizione_sede", "label",
        ]).flatMap(Notice.text(from:))

        guard let identity = rawID ?? name else { return nil }
        self.init(id: identity, name: name ?? identity)
    }

    /// Creates a site.
    ///
    /// - Parameters:
    ///   - id: The site's identifier.
    ///   - name: The site's name.
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One booked slot in a room.
nonisolated struct RoomBooking: Identifiable, Sendable, Hashable {
    /// The room's identifier and the slot's position within it.
    let id: String
    /// When the booking starts.
    let start: Date
    /// When it ends. Never earlier than ``start``.
    let end: Date
    /// What the room is busy with, where the payload says.
    let title: String?

    /// The booking as an interval.
    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// A room with whatever the bookings service knows to be booked in it.
///
/// Free time is derived rather than asked for: the service answers what is happening,
/// and ``freeSlots(in:minimumMinutes:)`` returns the gaps between those answers, which
/// is what a student is actually looking for.
nonisolated struct RoomSchedule: Identifiable, Sendable, Hashable {
    /// The room's identifier, falling back to its name when the payload has no id.
    let id: String
    /// The room's name, falling back to its identifier.
    let name: String
    /// The building it is in, where the payload says.
    let building: String?
    /// Seating capacity, where the payload says.
    let seats: Int?
    /// The `idaula`, for the equipment and software lookups. Filled in from the maps
    /// catalogue rather than by this payload.
    var occupancyID: String?
    /// What is booked in the room, sorted by start.
    var bookings: [RoomBooking]

    /// Reads a room out of a decoded payload, trying several candidate key spellings.
    ///
    /// A room with no bookings is kept: an empty list is the most interesting case, so it
    /// must not disqualify the row.
    ///
    /// - Parameters:
    ///   - fields: One room's fields.
    ///   - index: The room's position in the payload.
    /// - Returns: `nil` when neither an identifier nor a name can be found.
    init?(fields: [String: JSONValue], index: Int) {
        let rawID = fields.firstValue([
            "id_aula", "idAula", "id", "codice", "cod_aula", "csi_aula", "sigla",
        ])?.stringValue
        let name = fields.firstValue([
            "nome", "sigla", "descrizione", "denominazione", "name", "aula",
        ]).flatMap(Notice.text(from:))

        guard let identity = rawID ?? name else { return nil }

        // Bookings live under one of several plausible keys, and may be absent
        // entirely for a room with nothing on — which is the most interesting
        // case, so it must not disqualify the row.
        let slots = fields.firstValue([
            "impegni", "occupazioni", "eventi", "prenotazioni", "bookings",
            "events", "lezioni", "slots", "orari",
        ])?.arrayValue ?? []

        self.init(
            id: identity,
            name: name ?? identity,
            building: fields.firstValue([
                "edificio", "building", "nome_edificio", "descrizione_edificio",
            ]).flatMap(Notice.text(from:)),
            seats: fields.firstValue([
                "capienza", "posti", "seats", "capacity", "n_posti",
            ])?.intValue,
            bookings: slots.enumerated().compactMap { offset, slot in
                slot.objectValue.flatMap {
                    RoomBooking(fields: $0, roomID: identity, index: offset)
                }
            }
        )
    }

    /// Creates a room, sorting its bookings by start.
    ///
    /// - Parameters:
    ///   - id: The room's identifier.
    ///   - name: The room's name.
    ///   - building: The building it is in.
    ///   - seats: Seating capacity.
    ///   - occupancyID: The `idaula`, for the facilities lookups.
    ///   - bookings: What is booked in the room.
    init(id: String, name: String, building: String?, seats: Int?,
         occupancyID: String? = nil, bookings: [RoomBooking]) {
        self.id = id
        self.name = name
        self.building = building
        self.seats = seats
        self.occupancyID = occupancyID
        self.bookings = bookings.sorted { $0.start < $1.start }
    }

    /// Whether nothing is booked across an interval.
    ///
    /// Overlap is strict, so a lecture ending at 11:00 leaves the room free from 11:00.
    /// `DateInterval.intersects` treats intervals as closed and would call that a clash,
    /// hiding every room during the hour it becomes available.
    ///
    /// - Parameter interval: The span to test.
    /// - Returns: `true` when no booking overlaps it.
    func isFree(during interval: DateInterval) -> Bool {
        !bookings.contains { booking in
            booking.start < interval.end && interval.start < booking.end
        }
    }

    /// The free gaps within a day.
    ///
    /// Bookings are clipped to the day and merged first, because overlap is normal rather
    /// than exceptional — a lecture and an exam session booked over it are two rows
    /// covering the same hour, and subtracting them one at a time would report the second
    /// as free.
    ///
    /// - Parameters:
    ///   - day: The span to look within.
    ///   - minimumMinutes: The shortest gap worth reporting.
    /// - Returns: The gaps, in time order.
    func freeSlots(in day: DateInterval, minimumMinutes: Int = 30) -> [DateInterval] {
        let busy = RoomSchedule.merge(
            bookings.map(\.interval).compactMap { day.intersection(with: $0) }
        )

        var slots: [DateInterval] = []
        var cursor = day.start
        for block in busy {
            if block.start > cursor {
                slots.append(DateInterval(start: cursor, end: block.start))
            }
            cursor = max(cursor, block.end)
        }
        if cursor < day.end {
            slots.append(DateInterval(start: cursor, end: day.end))
        }

        let minimum = TimeInterval(minimumMinutes * 60)
        return slots.filter { $0.duration >= minimum }
    }

    /// Collapses overlapping or touching intervals into single blocks.
    ///
    /// - Parameter intervals: The intervals to merge, in any order.
    /// - Returns: The merged blocks, in time order.
    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}

/// Reading a booking out of the service's payload, and formatting its times.
nonisolated extension RoomBooking {
    /// Reads a booking out of a decoded payload, trying several candidate key spellings.
    ///
    /// A slot missing either end is dropped rather than guessed at: dropping it makes the
    /// room look busier than it is, and guessing could mark a busy room free.
    ///
    /// - Parameters:
    ///   - fields: One booking's fields.
    ///   - roomID: The room the booking belongs to.
    ///   - index: The booking's position within the room.
    /// - Returns: `nil` when either timestamp is missing or unparseable.
    init?(fields: [String: JSONValue], roomID: String, index: Int) {
        let startValue = fields.firstValue([
            "inizio", "data_inizio", "ora_inizio", "start", "start_date",
            "dataOraInizio", "from", "date_start",
        ])
        let endValue = fields.firstValue([
            "fine", "data_fine", "ora_fine", "end", "end_date",
            "dataOraFine", "to", "date_end",
        ])

        // A slot without both ends cannot be subtracted from the day, and
        // guessing one would mark a busy room free. Dropping it is the safe
        // direction: the room then looks busier than it is, never emptier.
        guard
            let start = startValue.flatMap(RoomBooking.moment(from:)),
            let end = endValue.flatMap(RoomBooking.moment(from:))
        else { return nil }

        self.init(
            id: "\(roomID)-\(index)",
            start: start,
            end: max(start, end),
            title: fields.firstValue([
                "descrizione", "titolo", "nome", "title", "evento",
                "insegnamento", "tipo", "attivita",
            ]).flatMap(Notice.text(from:))
        )
    }

    /// A booking's timestamp, in any of the forms these services use.
    ///
    /// - Parameter value: The decoded field.
    /// - Returns: The date, or `nil` when it cannot be read.
    static func moment(from value: JSONValue) -> Date? {
        Notice.date(from: value)
    }

    /// `HH:mm` in Rome — the clock the timetable is printed on, not the device's.
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// The `/cata/aule` payload: rooms, however they are wrapped.
nonisolated struct AuleResponse: Decodable, Sendable {
    /// The rooms read out of the payload. Empty when none could be.
    let rooms: [RoomSchedule]
    /// The payload as it arrived, for diagnostics.
    let raw: JSONValue

    /// Decodes the payload into ``JSONValue`` and extracts the rooms from it.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Only when the body is not JSON at all.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        rooms = AuleResponse.extract(from: value)
    }

    /// Reads rooms out of a decoded payload, whatever it is wrapped in.
    ///
    /// An array is read directly. An object is followed into the first named key that
    /// holds an array, then into any array-valued member, and finally read as a single
    /// room.
    ///
    /// - Parameter value: The decoded payload.
    /// - Returns: The rooms, or an empty array when none can be read.
    static func extract(from value: JSONValue) -> [RoomSchedule] {
        if let items = value.arrayValue {
            return items.enumerated().compactMap { index, item in
                item.objectValue.flatMap { RoomSchedule(fields: $0, index: index) }
            }
        }
        guard let fields = value.objectValue else { return [] }
        let candidates = ["aule", "rooms", "data", "items", "results",
                          "content", "list", "elenco", "AULE"]
        if let named = fields.firstValue(candidates), named.arrayValue != nil {
            return extract(from: named)
        }
        if let anyArray = fields.values.first(where: { $0.arrayValue != nil }) {
            return extract(from: anyArray)
        }
        return RoomSchedule(fields: fields, index: 0).map { [$0] } ?? []
    }
}

/// The `/cata/sedi` payload: campuses, however they are wrapped.
nonisolated struct SediResponse: Decodable, Sendable {
    /// The campuses read out of the payload.
    let sites: [AuleSite]
    /// The payload as it arrived, for diagnostics.
    let raw: JSONValue

    /// Decodes the payload into ``JSONValue`` and extracts the campuses from it.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Only when the body is not JSON at all.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        sites = SediResponse.extract(from: value)
    }

    /// Reads campuses out of a decoded payload, whatever it is wrapped in, by the same
    /// rules as ``AuleResponse/extract(from:)``.
    ///
    /// - Parameter value: The decoded payload.
    /// - Returns: The campuses, or an empty array when none can be read.
    static func extract(from value: JSONValue) -> [AuleSite] {
        if let items = value.arrayValue {
            return items.enumerated().compactMap { index, item in
                item.objectValue.flatMap { AuleSite(fields: $0, index: index) }
            }
        }
        guard let fields = value.objectValue else { return [] }
        if let named = fields.firstValue(["sedi", "sites", "data", "items", "elenco"]),
           named.arrayValue != nil {
            return extract(from: named)
        }
        if let anyArray = fields.values.first(where: { $0.arrayValue != nil }) {
            return extract(from: anyArray)
        }
        return AuleSite(fields: fields, index: 0).map { [$0] } ?? []
    }
}

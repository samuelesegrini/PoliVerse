import Foundation

/// A campus, as the bookings service names them.
nonisolated struct AuleSite: Identifiable, Sendable, Hashable {
    let id: String
    let name: String

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

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One booked slot in a room.
nonisolated struct RoomBooking: Identifiable, Sendable, Hashable {
    let id: String
    let start: Date
    let end: Date
    /// What the room is busy with, where the payload says.
    let title: String?

    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// A room, with whatever the service knows to be booked in it.
///
/// The point of the type: free time is **derived** from the bookings rather
/// than asked for. The service answers "what is happening", and the gaps
/// between those answers are what a student actually wants.
nonisolated struct RoomSchedule: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let building: String?
    let seats: Int?
    /// `idaula`, for the equipment and software lookups.
    var occupancyID: String?
    var bookings: [RoomBooking]

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

    init(id: String, name: String, building: String?, seats: Int?,
         occupancyID: String? = nil, bookings: [RoomBooking]) {
        self.id = id
        self.name = name
        self.building = building
        self.seats = seats
        self.occupancyID = occupancyID
        self.bookings = bookings.sorted { $0.start < $1.start }
    }

    /// Whether nothing is booked across `interval`.
    ///
    /// Overlap is strict: a lecture ending at 11:00 leaves the room free from
    /// 11:00. `DateInterval.intersects` treats intervals as closed and would
    /// call that a clash, which would hide every room during the hour it
    /// becomes available — the most useful hour there is.
    func isFree(during interval: DateInterval) -> Bool {
        !bookings.contains { booking in
            booking.start < interval.end && interval.start < booking.end
        }
    }

    /// The free gaps within `day`, merging bookings that overlap or touch.
    ///
    /// Overlap is normal rather than exceptional: a lecture and the exam
    /// session booked over it are two rows covering the same hour, and
    /// subtracting them one at a time would report the second as free.
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

    /// Collapses overlapping or adjacent intervals into single blocks.
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

nonisolated extension RoomBooking {
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
    static func moment(from value: JSONValue) -> Date? {
        Notice.date(from: value)
    }

    /// `HH:mm` for the UI, in Rome — the same clock the timetable is printed
    /// on, not the device's.
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
    let rooms: [RoomSchedule]
    let raw: JSONValue

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        rooms = AuleResponse.extract(from: value)
    }

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

/// The `/cata/sedi` payload.
nonisolated struct SediResponse: Decodable, Sendable {
    let sites: [AuleSite]
    let raw: JSONValue

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        raw = value
        sites = SediResponse.extract(from: value)
    }

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

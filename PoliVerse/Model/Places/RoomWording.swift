import Foundation

/// Where a room is, in the words Cerca's room card uses: "Edificio 3, primo piano".
///
/// The floor catalogue names floors in one word — "Primo", "Terra", "Seminterrato",
/// "Terra Soppalco" — which reads wrong on its own. This turns them into what a student
/// would say, lower case so it can follow a comma or sit inside a sentence. Pure, so every
/// name the catalogue sends is tested.
nonisolated enum RoomWording {
    /// The Italian ordinals the catalogue writes, first to twelfth.
    private static let ordinals = [
        "primo", "secondo", "terzo", "quarto", "quinto", "sesto",
        "settimo", "ottavo", "nono", "decimo", "undicesimo", "dodicesimo",
    ]

    /// The floor as a student says it: "piano terra", "primo piano", "seminterrato".
    ///
    /// - Parameters:
    ///   - name: The floor catalogue's name, where the room has one.
    ///   - code: The floor's code, `csip`, read when there is no name: its last three
    ///     characters are the floor.
    /// - Returns: The phrase in lower case, or `nil` when neither says which floor it is.
    static func floor(name: String?, code: String?) -> String? {
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return floor(named: name)
        }
        guard let code, code.count >= 3 else { return nil }
        switch code.suffix(3) {
        case "000": return String(localized: "piano terra")
        case "00S": return String(localized: "seminterrato")
        case "S00": return String(localized: "soppalco")
        default:
            guard let number = Int(code.suffix(3)) else { return nil }
            return ordinalFloor(number)
        }
    }

    /// The phrase for a floor catalogue name.
    private static func floor(named name: String) -> String {
        let lower = name.lowercased()
        // Already a phrase, as the samples write it: "Primo piano", "Piano terra".
        if lower.contains("piano") { return lower }
        if lower.hasSuffix(" soppalco") {
            let base = String(lower.dropLast(" soppalco".count))
            return String(localized: "soppalco del \(floor(named: base))")
        }
        switch lower {
        case "terra": return String(localized: "piano terra")
        case "rialzato": return String(localized: "piano rialzato")
        default:
            if let index = ordinals.firstIndex(of: lower) { return ordinalFloor(index + 1) }
            return lower
        }
    }

    /// "primo piano" for 1, "secondo piano" for 2; "piano 14" past the ordinals written out.
    private static func ordinalFloor(_ number: Int) -> String {
        guard number > 0 else { return String(localized: "piano terra") }
        guard number <= ordinals.count else { return String(localized: "piano \(number)") }
        switch number {
        case 1: return String(localized: "primo piano")
        case 2: return String(localized: "secondo piano")
        case 3: return String(localized: "terzo piano")
        case 4: return String(localized: "quarto piano")
        case 5: return String(localized: "quinto piano")
        case 6: return String(localized: "sesto piano")
        default: return "\(ordinals[number - 1]) piano"
        }
    }

    /// "1 posto", "96 posti".
    static func seats(_ count: Int, locale: Locale = .current) -> String {
        count == 1 ? String(localized: "1 posto", locale: locale) : String(localized: "\(count) posti", locale: locale)
    }

    /// "1 accessibile", "2 accessibili".
    static func accessibleSeats(_ count: Int, locale: Locale = .current) -> String {
        count == 1 ? String(localized: "1 accessibile", locale: locale)
            : String(localized: "\(count) accessibili", locale: locale)
    }

    /// "Edificio 3, primo piano": the building, then the floor, joined by a comma.
    ///
    /// - Parameter room: The room.
    /// - Returns: The line; the campus when neither building nor floor is known; empty when
    ///   nothing is.
    static func location(of room: Classroom) -> String {
        let parts = [room.buildingName, floor(name: room.floorName, code: room.floorCode)]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
        if parts.isEmpty { return room.campusName ?? "" }
        return parts.joined(separator: ", ")
    }

    /// "primo piano dell'Edificio 3", for the line under the full-screen photo.
    ///
    /// - Parameter room: The room.
    /// - Returns: The phrase, or `nil` when the floor is not known.
    static func floorOfBuilding(_ room: Classroom) -> String? {
        guard let floor = floor(name: room.floorName, code: room.floorCode) else { return nil }
        guard let building = room.buildingName, !building.isEmpty else { return floor }
        return String(localized: "\(floor) dell'\(building)")
    }

    /// "96 posti, 2 accessibili, primo piano dell'Edificio 3".
    ///
    /// - Parameter room: The room.
    /// - Returns: The facts that are known, joined by commas.
    static func facts(of room: Classroom) -> String {
        var parts = [seats(room.capacity)]
        if let accessible = room.accessibleSeats, accessible > 0 {
            parts.append(accessibleSeats(accessible))
        }
        if let floor = floorOfBuilding(room) { parts.append(floor) }
        return parts.joined(separator: ", ")
    }
}

/// What a room is doing now, in the words and shape of Cerca's room card: the headline
/// ("Libera ora"), when that changes ("fino alle 14:15"), the one-line form for the compact
/// card ("Libera fino alle 14:15"), the line under the bar ("Ancora 1 h 30 min prima di
/// Analisi 1") and how much of the free spell is left, for the bar.
///
/// Worked out from ``MapRoomStatus`` and the bookings ``FreeRoomsModel/bookings(for:)``
/// returns. Unknown is said plainly and never drawn as free. Pure, so every branch is tested.
nonisolated struct RoomStatusText: Equatable, Sendable {
    /// The colour the headline is written in.
    enum Tone: Equatable, Sendable {
        /// Free now: green.
        case free
        /// Booked now: red.
        case busy
        /// Not known, or outside the teaching day: grey.
        case unknown
    }

    /// The colour of the headline.
    let tone: Tone
    /// "Libera ora", "Occupata", "Stato non disponibile".
    let headline: String
    /// "fino alle 14:15", "per il resto della giornata"; `nil` when there is nothing to add.
    let until: String?
    /// The status in one line, for the compact card: "Libera fino alle 14:15".
    let compact: String
    /// The line under the bar: "Ancora 1 h 30 min prima di Analisi 1", or what the room is
    /// busy with.
    let detail: String?
    /// How much of the current free spell is left, 0 to 1, for the bar; `nil` draws none.
    let remaining: Double?

    /// "45 min", "1 h", "1 h 30 min".
    ///
    /// - Parameter interval: The span, rounded down to the minute and never below one.
    /// - Returns: The span in hours and minutes.
    static func span(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.down)))
        if minutes < 60 { return String(localized: "\(minutes) min") }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
    }

    /// The status of a room at a moment.
    ///
    /// - Parameters:
    ///   - bookings: The room's bookings for the day, or `nil` when they are unknown.
    ///   - isLoading: Whether the bookings are still being read.
    ///   - now: The moment to read against.
    ///   - day: The teaching day; outside it nothing is claimed.
    ///   - locale: The locale times are written in.
    ///   - timeZone: The time zone the clock is read in.
    /// - Returns: The words for the card.
    static func make(bookings: [RoomBooking]?, isLoading: Bool = false, now: Date, day: DateInterval,
                     locale: Locale = .current, timeZone: TimeZone = .current) -> RoomStatusText {
        func clock(_ date: Date) -> String {
            var style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
            style.timeZone = timeZone
            return date.formatted(style)
        }
        if isLoading, bookings == nil {
            let text = String(localized: "Controllo le prenotazioni…", locale: locale)
            return RoomStatusText(tone: .unknown, headline: text, until: nil, compact: text, detail: nil, remaining: nil)
        }
        guard day.contains(now) else {
            let text = String(localized: "Fuori dall'orario delle lezioni", locale: locale)
            return RoomStatusText(tone: .unknown, headline: text, until: nil, compact: text, detail: nil, remaining: nil)
        }
        switch MapRoomStatus.of(bookings, at: now, dayEnd: day.end) {
        case .unknown:
            let text = String(localized: "Stato non disponibile", locale: locale)
            return RoomStatusText(tone: .unknown, headline: text, until: nil, compact: text,
                                  detail: String(localized: "Il Politecnico non pubblica le prenotazioni di quest'aula.", locale: locale),
                                  remaining: nil)
        case .busy(let until, let what):
            let time = clock(until)
            return RoomStatusText(
                tone: .busy,
                headline: String(localized: "Occupata", locale: locale),
                until: String(localized: "fino alle \(time)", locale: locale),
                compact: String(localized: "Occupata fino alle \(time)", locale: locale),
                detail: what,
                remaining: nil)
        case .free(let until):
            let sorted = (bookings ?? []).sorted { $0.start < $1.start }
            // The spell began when the last booking before now ended, or when the day did.
            let began = sorted.last { $0.end <= now }.map { max($0.end, day.start) } ?? day.start
            guard let until else {
                let remaining = day.end.timeIntervalSince(now) / max(day.end.timeIntervalSince(began), 1)
                return RoomStatusText(
                    tone: .free,
                    headline: String(localized: "Libera ora", locale: locale),
                    until: String(localized: "per il resto della giornata", locale: locale),
                    compact: String(localized: "Libera per il resto della giornata", locale: locale),
                    detail: nil,
                    remaining: min(max(remaining, 0), 1))
            }
            let time = clock(until)
            let next = sorted.first { $0.start >= until }
            let left = span(until.timeIntervalSince(now))
            let detail = next?.title.map { String(localized: "Ancora \(left) prima di \($0)", locale: locale) }
                ?? String(localized: "Ancora \(left) prima della prossima prenotazione", locale: locale)
            let remaining = until.timeIntervalSince(now) / max(until.timeIntervalSince(began), 1)
            return RoomStatusText(
                tone: .free,
                headline: String(localized: "Libera ora", locale: locale),
                until: String(localized: "fino alle \(time)", locale: locale),
                compact: String(localized: "Libera fino alle \(time)", locale: locale),
                detail: detail,
                remaining: min(max(remaining, 0), 1))
        }
    }
}

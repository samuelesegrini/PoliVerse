import Foundation

// The services the new map (``BetaFeature/newMap``) points to besides the rooms: where to eat,
// drink, park, find a toilet or a quiet place to study.
//
// Two public sources of the maps service, no token:
// - `POST /poi/list` — the points of interest the official map draws: bars with their hours,
//   water fountains, defibrillators, bike racks, car parks with their free spaces.
// - `GET /piano/{csip}/tematismi` — per floor, what its spaces are used for ("Destinazioni
//   uso"): the public toilets, the libraries and the study spaces are only there.

/// A kind of service the map can show.
nonisolated enum CampusService: String, CaseIterable, Sendable, Identifiable {
    case bar, water, toilets, bikes, parking, defibrillator, study

    var id: String { rawValue }

    /// The chip's name.
    var title: String {
        switch self {
        case .bar: String(localized: "Bar")
        case .water: String(localized: "Acqua")
        case .toilets: String(localized: "Bagni")
        case .bikes: String(localized: "Bici")
        case .parking: String(localized: "Parcheggio")
        case .defibrillator: String(localized: "Defibrillatore")
        case .study: String(localized: "Studio")
        }
    }

    /// The panel's title while the service is shown.
    var heading: String {
        switch self {
        case .bar: String(localized: "Bar e ristoro")
        case .water: String(localized: "Acqua da bere")
        case .toilets: String(localized: "Bagni")
        case .bikes: String(localized: "Posti bici")
        case .parking: String(localized: "Parcheggi")
        case .defibrillator: String(localized: "Defibrillatori")
        case .study: String(localized: "Biblioteche e studio")
        }
    }

    /// The SF Symbol.
    var symbol: String {
        switch self {
        case .bar: "cup.and.saucer.fill"
        case .water: "drop.fill"
        case .toilets: "toilet.fill"
        case .bikes: "bicycle"
        case .parking: "parkingsign"
        case .defibrillator: "bolt.heart.fill"
        case .study: "books.vertical.fill"
        }
    }

    /// Whether its places come from the floors' uses rather than the points of interest.
    var isPerFloor: Bool { self == .toilets || self == .study }

    /// The service a point of interest's tag stands for, `nil` for the ones not shown.
    ///
    /// - Parameter tag: The tag as the service sends it, for example `24317_LBL_TAG_RISTORO`.
    static func of(tag: String) -> CampusService? {
        switch tag.replacingOccurrences(of: "24317_LBL_TAG_", with: "") {
        case "RISTORO": .bar
        case "BEVERINO": .water
        case "STALLO_BICI", "VELOSTAZIONE": .bikes
        case "PARCHEGGIO": .parking
        case "DAE": .defibrillator
        default: nil
        }
    }
}

/// When something is open in a week: one span of days at the same hours.
nonisolated struct OpeningSpan: Sendable, Equatable {
    /// The days, as `Calendar` numbers them: 1 is Sunday, 2 Monday, 7 Saturday.
    let weekdays: Set<Int>
    /// Opening, in minutes after midnight.
    let opens: Int
    /// Closing, in minutes after midnight.
    let closes: Int
}

/// Whether something is open at a moment.
nonisolated enum Openness: Sendable, Equatable {
    /// Open, closing at this minute of the day.
    case open(closes: Int)
    /// Closed now, opening later today at this minute.
    case opensLater(at: Int)
    /// Closed for the rest of the day.
    case closed
}

/// Reads opening hours as the maps service writes them.
nonisolated enum OpeningHours {
    /// The Italian days, by the first three letters, as `Calendar` numbers them.
    private static let days = ["dom": 1, "lun": 2, "mar": 3, "mer": 4, "gio": 5, "ven": 6, "sab": 7]

    /// Reads one line of hours: "lun-ven 8:00 – 19:00", "lun – ven 11:30 – 14:30",
    /// "Da lunedì a sabato: 7.30 - 20.30", "8:00 – 15:00".
    ///
    /// - Parameter text: The line, in Italian.
    /// - Returns: The span, or `nil` without two times. Without days, Monday to Friday, as
    ///   the lines that leave them out sit next to a "lun-ven" one.
    static func parse(_ text: String) -> OpeningSpan? {
        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter }.map(String.init)
        let named = words.compactMap { word in word.count >= 3 ? days[String(word.prefix(3))] : nil }
        let weekdays: Set<Int>
        switch named.count {
        case 0: weekdays = Set(2...6)
        case 1: weekdays = [named[0]]
        default: weekdays = range(from: named[0], to: named[1])
        }
        let times = minutes(in: lower)
        guard times.count >= 2, times[1] > times[0] else { return nil }
        return OpeningSpan(weekdays: weekdays, opens: times[0], closes: times[1])
    }

    /// Reads the car parks' hours: `{"lunedi": [{"inizio": "07:00", "fine": "20:30"}], …}`.
    ///
    /// - Parameter week: The days by Italian name, each with its intervals.
    /// - Returns: A span per interval.
    static func parse(week: [String: [[String: String]]]) -> [OpeningSpan] {
        week.flatMap { day, intervals -> [OpeningSpan] in
            guard let weekday = days[String(day.lowercased().prefix(3))] else { return [] }
            return intervals.compactMap { interval in
                guard let start = interval["inizio"].flatMap({ minutes(in: $0).first }),
                      let end = interval["fine"].flatMap({ minutes(in: $0).first }), end > start
                else { return nil }
                return OpeningSpan(weekdays: [weekday], opens: start, closes: end)
            }
        }
        .sorted { ($0.weekdays.min() ?? 0, $0.opens) < ($1.weekdays.min() ?? 0, $1.opens) }
    }

    /// Whether the spans are open at a moment.
    ///
    /// - Parameters:
    ///   - spans: The spans.
    ///   - weekday: The day, as `Calendar` numbers them.
    ///   - minute: Minutes after midnight.
    /// - Returns: Open until the latest closing among the spans open now; else the next
    ///   opening today; else closed.
    static func state(_ spans: [OpeningSpan], weekday: Int, minute: Int) -> Openness {
        let today = spans.filter { $0.weekdays.contains(weekday) }
        let open = today.filter { $0.opens <= minute && minute < $0.closes }
        if let closes = open.map(\.closes).max() { return .open(closes: closes) }
        if let next = today.map(\.opens).filter({ $0 > minute }).min() { return .opensLater(at: next) }
        return .closed
    }

    /// "8:00", "15:30": a minute of the day as a clock.
    static func clock(_ minute: Int) -> String {
        String(format: "%d:%02d", minute / 60, minute % 60)
    }

    /// The days from one to another, wrapping past Saturday.
    private static func range(from start: Int, to end: Int) -> Set<Int> {
        var result: Set<Int> = [start]
        var day = start
        while day != end, result.count < 7 {
            day = day % 7 + 1
            result.insert(day)
        }
        return result
    }

    /// Every "8:00" or "8.00" in a text, as minutes after midnight, in order.
    private static func minutes(in text: String) -> [Int] {
        text.matches(of: /(\d{1,2})[:.](\d{2})/).compactMap { match in
            guard let hour = Int(match.output.1), let minute = Int(match.output.2),
                  hour < 24, minute < 60 else { return nil }
            return hour * 60 + minute
        }
    }
}

/// A place offering a service.
nonisolated struct CampusPlace: Sendable, Equatable, Identifiable {
    /// Unique across services.
    let id: String
    /// What it offers.
    let service: CampusService
    /// What the row calls it: the bar's name, the car park's, the rack's. `nil` for the
    /// places named by their building, such as a fountain or a toilet.
    let name: String?
    /// Where it is, in the service's words: "Edificio 3, terra".
    let detail: String?
    /// Its building's code, where known.
    let csie: String?
    /// Its floor's code, where known.
    let csip: String?
    /// Where it stands, where the service says.
    let latitude: Double?
    /// Where it stands, where the service says.
    let longitude: Double?
    /// When it is open; empty when the service gives no hours.
    var hours: [OpeningSpan] = []
    /// A car park's free spaces now, or a rack's spaces.
    var spaces: Int?
    /// A car park's capacity.
    var capacity: Int?
    /// A toilet for wheelchair users; a library rather than a study space.
    var special = false

    /// The area of campuses it is in, the first three letters of its codes: `MIA` for Città
    /// Studi, `MIB` for Bovisa.
    var area: String? {
        (csip ?? csie ?? areaCode).map { String($0.prefix(3)) }
    }
    /// The code the point of interest is filed under when it has no building, such as a car
    /// park's `MIA04`.
    var areaCode: String? = nil
}

/// Reads the services' places from the maps service.
nonisolated enum CampusPlaces {
    /// The places among the points of interest, for the services shown.
    ///
    /// - Parameters:
    ///   - data: The body of `POST /poi/list`.
    ///   - language: `"it"` or `"en"`, for the texts sent in both.
    /// - Returns: A place per point and service; points under two shown services appear
    ///   under each.
    static func parse(_ data: Data, language: String = "it") throws -> [CampusPlace] {
        guard let points = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return points.flatMap { point -> [CampusPlace] in
            let tags = (point["tags"] as? [String: String]).map { Array($0.values) } ?? []
            let services = Set(tags.compactMap(CampusService.of(tag:)))
            guard !services.isEmpty else { return [] }
            let props = point["props"] as? [String: Any] ?? [:]
            let location = point["location"] as? [String: Any] ?? [:]
            let csi = location["csi"] as? String ?? ""
            let id = point["id"].map { "\($0)" } ?? UUID().uuidString
            func text(_ key: String) -> String? { localized(props[key], language) }
            return services.sorted { $0.rawValue < $1.rawValue }.map { service in
                var place = CampusPlace(
                    id: "\(service.rawValue)-\(id)", service: service,
                    name: name(for: service, props: props, language: language),
                    detail: service == .bar || service == .bikes || service == .parking
                        ? text("ubicazione") ?? props["indirizzo"] as? String
                        : text("denominazione"),
                    csie: csi.count >= 7 ? String(csi.prefix(7)) : nil,
                    csip: csi.count == 10 ? csi : nil,
                    latitude: location["lat"] as? Double, longitude: location["lng"] as? Double,
                    areaCode: csi.isEmpty ? nil : csi)
                switch service {
                case .bar:
                    let lines = (props["orario"] as? [String: Any])?["it"] as? [String: String] ?? [:]
                    place.hours = lines.values.compactMap(OpeningHours.parse)
                case .parking:
                    if let week = props["orari_apertura"] as? [String: [[String: String]]] {
                        place.hours = OpeningHours.parse(week: week)
                    }
                    let free = props["posti_liberi"] as? [String: Any]
                    place.spaces = (free?["standard"] as? NSNumber)?.intValue
                    place.capacity = (props["capienza_totale"] as? NSNumber)?.intValue
                        ?? (props["totale_auto"] as? NSNumber)?.intValue
                case .bikes:
                    let counts = props["numero_posti"] as? [String: Any] ?? [:]
                    let total = ["in_rastrelliera", "in_archetto", "in_parkup"]
                        .compactMap { (counts[$0] as? NSNumber)?.intValue }.reduce(0, +)
                    place.spaces = total > 0 ? total : nil
                    if let line = (props["orario"] as? [String: Any])?["it"] as? String,
                       let span = OpeningHours.parse(line) {
                        place.hours = [span]
                    }
                default:
                    break
                }
                return place
            }
        }
    }

    /// The row's name: the bar's, the car park's, the rack's; none for a fountain or a
    /// defibrillator, which are named by their building.
    private static func name(for service: CampusService, props: [String: Any], language: String) -> String? {
        switch service {
        case .bar, .bikes: localized(props["denominazione"], language) ?? props["name"] as? String
        case .parking: props["name"] as? String
        default: nil
        }
    }

    /// A text the service sends either plain or as `{"it": …, "en": …}`.
    private static func localized(_ value: Any?, _ language: String) -> String? {
        let text: String? = switch value {
        case let plain as String: plain
        case let both as [String: Any]: (both[language] as? String) ?? (both["it"] as? String)
        default: nil
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// The places of the per-floor services on one floor.
    ///
    /// - Parameters:
    ///   - uses: The floor's uses, as ``FloorUses/parse(_:)`` reads them.
    ///   - csip: The floor's code.
    /// - Returns: A toilet when the floor has a public one (accessible when one of them is),
    ///   and a study place when it has a library or a study space (a library first).
    static func onFloor(_ uses: Set<String>, csip: String) -> [CampusPlace] {
        var places: [CampusPlace] = []
        let csie = csip.count >= 7 ? String(csip.prefix(7)) : nil
        if uses.contains("WC PUBBLICO") || uses.contains("WC DISABILE PUBBLICO") {
            places.append(CampusPlace(id: "toilets-\(csip)", service: .toilets, name: nil, detail: nil,
                                      csie: csie, csip: csip, latitude: nil, longitude: nil,
                                      special: uses.contains("WC DISABILE PUBBLICO")))
        }
        let library = uses.contains("BIBLIOTECA E SPAZIO CONSULTAZIONE")
        if library || uses.contains("SPAZIO STUDIO") || uses.contains("SPAZIO ESTERNO STUDIO") {
            places.append(CampusPlace(id: "study-\(csip)", service: .study,
                                      name: library ? String(localized: "Biblioteca") : String(localized: "Spazio studio"),
                                      detail: nil, csie: csie, csip: csip, latitude: nil, longitude: nil,
                                      special: library))
        }
        return places
    }

    /// The places nearest first: the origin's building, then by distance, the unmeasured
    /// last, ties by floor and name.
    ///
    /// - Parameters:
    ///   - places: The places.
    ///   - origin: The building the student starts from.
    ///   - metres: Each place's distance from the origin, by ``CampusPlace/id``, where known.
    static func nearest(_ places: [CampusPlace], origin: String?, metres: [String: Double]) -> [CampusPlace] {
        func rank(_ place: CampusPlace) -> Double {
            if let origin, place.csie == origin { return -1 }
            return metres[place.id] ?? .infinity
        }
        return places.sorted { left, right in
            let a = rank(left), b = rank(right)
            if a != b { return a < b }
            let l = (left.csip ?? "") + (left.name ?? ""), r = (right.csip ?? "") + (right.name ?? "")
            return l.localizedStandardCompare(r) == .orderedAscending
        }
    }
}

/// What a floor's spaces are used for.
nonisolated enum FloorUses {
    /// The theme that lists the uses.
    static let theme = 1030

    /// The uses on a floor, from `GET /piano/{csip}/tematismi`.
    ///
    /// - Parameter data: The body.
    /// - Returns: The uses in capitals, as sent: "WC PUBBLICO", "SPAZIO STUDIO", …
    static func parse(_ data: Data) throws -> Set<String> {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let themes = body["result"] as? [[String: Any]] else { return [] }
        let uses = themes.first { ($0["tema_id"] as? NSNumber)?.intValue == theme }
        let items = uses?["voci"] as? [[String: Any]] ?? []
        return Set(items.compactMap { $0["description"] as? String })
    }
}

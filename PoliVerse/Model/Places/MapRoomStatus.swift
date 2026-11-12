import Foundation

/// Whether a classroom is free now, and until when, from its bookings for the day.
///
/// What the new map (``BetaFeature/newMap``) writes next to every room. Worked out from the
/// bookings ``FreeRoomsModel/bookings(for:)`` already fetches, so no request is spent on it.
nonisolated enum MapRoomStatus: Equatable, Sendable {
    /// The bookings have not been read, or the university does not publish them. Never shown
    /// as free.
    case unknown
    /// Free now: until the next booking, or with `nil` for the rest of the teaching day.
    case free(until: Date?)
    /// Booked now until `until`, which runs on through bookings that follow with a gap
    /// shorter than ``joinGap``, with what the first is, where the payload says.
    case busy(until: Date, what: String?)

    /// The longest gap between two bookings that still reads as one: a quarter of an hour is
    /// the break between two lessons, not time to sit down and study.
    static let joinGap: TimeInterval = 15 * 60

    /// The status at a moment.
    ///
    /// - Parameters:
    ///   - bookings: The room's bookings for the day, or `nil` when they are unknown.
    ///   - now: The moment to read against.
    ///   - dayEnd: The end of the teaching day: a booking after it does not end a free spell.
    /// - Returns: The status.
    static func of(_ bookings: [RoomBooking]?, at now: Date, dayEnd: Date) -> MapRoomStatus {
        guard let bookings else { return .unknown }
        let sorted = bookings.sorted { $0.start < $1.start }
        if let current = sorted.first(where: { $0.start <= now && now < $0.end }) {
            var end = current.end
            for booking in sorted where booking.start > current.start && booking.start <= end + joinGap {
                end = max(end, booking.end)
            }
            return .busy(until: end, what: current.title)
        }
        if let next = sorted.first(where: { $0.start > now }), next.start < dayEnd {
            return .free(until: next.start)
        }
        return .free(until: nil)
    }

    /// Whether the room can be used now.
    var isFree: Bool {
        if case .free = self { true } else { false }
    }
}

/// The counts the new map writes, in Italian that agrees with the number: "1 aula", "3 aule",
/// "1 libera su 4", "nessuna libera su 4". Automatic grammar agreement inflects the word next
/// to the number, so one string covers singular and plural.
nonisolated enum MapCounts {
    /// "nessuna aula", "1 aula", "12 aule".
    static func rooms(_ count: Int, locale: Locale = .current) -> String {
        guard count > 0 else { return String(localized: "nessuna aula", locale: locale) }
        return inflected(AttributedString(localized: "^[\(count) aula](inflect: true)", locale: locale))
    }

    /// "1 piano", "5 piani".
    static func floors(_ count: Int, locale: Locale = .current) -> String {
        inflected(AttributedString(localized: "^[\(count) piano](inflect: true)", locale: locale))
    }

    /// "nessuna libera su 4", "1 libera su 4", "3 libere su 4".
    static func free(_ free: Int, of total: Int, locale: Locale = .current) -> String {
        guard free > 0 else { return String(localized: "nessuna libera su \(total)", locale: locale) }
        return inflected(AttributedString(localized: "^[\(free) libera](inflect: true) su \(total)", locale: locale))
    }

    /// "nessuna libera ora", "1 libera ora", "12 libere ora".
    static func freeNow(_ free: Int, locale: Locale = .current) -> String {
        guard free > 0 else { return String(localized: "nessuna libera ora", locale: locale) }
        return inflected(AttributedString(localized: "^[\(free) libera](inflect: true) ora", locale: locale))
    }

    /// "Nessuna aula libera ora", "1 aula libera ora", "12 aule libere ora".
    static func freeNowTitle(_ free: Int, locale: Locale = .current) -> String {
        guard free > 0 else { return String(localized: "Nessuna aula libera ora", locale: locale) }
        return inflected(AttributedString(localized: "^[\(free) aula libera](inflect: true) ora", locale: locale))
    }

    private static func inflected(_ text: AttributedString) -> String {
        String(text.characters)
    }
}

/// One of the student's own lessons, which the room's sentence names instead of "occupata".
nonisolated struct MapOwnLesson: Sendable, Equatable {
    /// The course's name.
    let title: String
    /// When it is held.
    let interval: DateInterval
}

/// The colour a room's sentence is written in.
nonisolated enum MapRoomTone: Sendable, Equatable {
    /// Free now: green.
    case free
    /// Booked now: red.
    case busy
    /// The student's own lesson is on now: the tint.
    case mine
    /// Nothing is known: grey.
    case unknown
}

/// What a room is doing and what happens next, in one sentence: "**Occupata** da Fisica I
/// fino alle **12:15**, poi **libera** fino alle **14:15**." or "**Libera** ancora per
/// **20 minuti**, poi **la tua lezione di Analisi II**." The text is inline Markdown, with
/// the parts that matter in bold; ``styled(_:)`` turns it into the attributed string shown.
/// Pure, so every branch is tested.
nonisolated enum MapRoomSentence {
    /// The sentence and its tone.
    ///
    /// - Parameters:
    ///   - bookings: The room's bookings for the day, or `nil` when they are unknown.
    ///   - own: The student's own lessons in the room today.
    ///   - now: The moment to read against.
    ///   - dayEnd: The end of the teaching day.
    ///   - locale: The locale times and numbers are written in.
    /// The sentence as shown: plain text, bold where the Markdown says.
    static func styled(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }

    static func make(bookings: [RoomBooking]?, own: [MapOwnLesson], now: Date, dayEnd: Date,
                     locale: Locale = .current) -> (text: String, tone: MapRoomTone) {
        guard let bookings else {
            return (String(localized: "Stato non disponibile", locale: locale), .unknown)
        }
        if now >= dayEnd {
            return (String(localized: "**Libera**: niente in programma fino a domani.", locale: locale), .free)
        }
        let sorted = bookings.sorted { $0.start < $1.start }
        func clock(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(locale)) }
        func mine(_ booking: RoomBooking) -> MapOwnLesson? {
            own.first { ($0.interval.intersection(with: booking.interval)?.duration ?? 0) > 0 }
        }
        /// The end of a booking, run on through the next ones that are not the student's.
        func joinedEnd(from booking: RoomBooking) -> Date {
            var end = booking.end
            for next in sorted where next.start > booking.start && next.start <= end + MapRoomStatus.joinGap {
                if mine(next) != nil { break }
                end = max(end, next.end)
            }
            return end
        }

        if let current = sorted.first(where: { $0.start <= now && now < $0.end }) {
            if let lesson = mine(current) {
                let end = max(current.end, lesson.interval.end)
                return (String(localized: "C'è **la tua lezione di \(lesson.title)** fino alle **\(clock(end))**.", locale: locale), .mine)
            }
            let end = joinedEnd(from: current)
            let head = current.title.map { String(localized: "**Occupata** da \($0) fino alle **\(clock(end))**", locale: locale) }
                ?? String(localized: "**Occupata** fino alle **\(clock(end))**", locale: locale)
            let next = sorted.first { $0.start >= end && $0.start < dayEnd }
            let tail: String
            if let next, let lesson = mine(next), next.start <= end + MapRoomStatus.joinGap {
                tail = String(localized: ", poi **la tua lezione di \(lesson.title)**.", locale: locale)
            } else if let next {
                tail = String(localized: ", poi **libera** fino alle **\(clock(next.start))**.", locale: locale)
            } else {
                tail = String(localized: ", poi **libera** per il resto della giornata.", locale: locale)
            }
            return (head + tail, .busy)
        }

        guard let next = sorted.first(where: { $0.start > now && $0.start < dayEnd }) else {
            return (String(localized: "**Libera** per il resto della giornata.", locale: locale), .free)
        }
        let minutes = Int((next.start.timeIntervalSince(now) / 60).rounded(.down))
        let lesson = mine(next)
        if minutes < 60 {
            let span = String(AttributedString(
                localized: "^[\(max(minutes, 1)) minuto](inflect: true)", locale: locale).characters)
            let head = String(localized: "**Libera** ancora per **\(span)**", locale: locale)
            let tail: String
            if let lesson {
                tail = String(localized: ", poi **la tua lezione di \(lesson.title)**.", locale: locale)
            } else {
                let end = clock(joinedEnd(from: next))
                tail = next.title.map { String(localized: ", poi **\($0)** fino alle **\(end)**.", locale: locale) }
                    ?? String(localized: ", poi **occupata** fino alle **\(end)**.", locale: locale)
            }
            return (head + tail, .free)
        }
        let head = String(localized: "**Libera** fino alle **\(clock(next.start))**", locale: locale)
        let tail = lesson.map { String(localized: ", poi **la tua lezione di \($0.title)**.", locale: locale) } ?? "."
        return (head + tail, .free)
    }
}

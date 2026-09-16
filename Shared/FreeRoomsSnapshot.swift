import Foundation

/// A day's room bookings, flattened to what a widget can use, per campus.
///
/// The widget deliberately does **no** networking. The alternative was moving
/// the catalogue and the bookings service into the extension, which would drag
/// the tolerant-JSON layer and half the models with them — and buy nothing,
/// because the bookings for a day are fetched once and do not change during
/// it. Storing the busy intervals means the widget can still answer "free
/// *now*" correctly at any moment, by comparing them against the clock at
/// render time rather than against a precomputed answer that goes stale.
nonisolated struct FreeRoomsSnapshot: Codable, Sendable, Equatable {
    /// The day these bookings describe. A snapshot from yesterday is not a
    /// stale answer, it is an answer to a different question, and the widget
    /// says so rather than showing it.
    var day: Date
    var campus: String
    var rooms: [Room]

    nonisolated struct Room: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var name: String
        var building: String?
        var seats: Int?
        /// When the room is taken, in order. Everything else is free.
        var busy: [Interval]
    }

    /// `DateInterval` is `Codable`, but its decoder traps on `end < start`,
    /// and a cache file is exactly where a malformed pair can arrive from.
    nonisolated struct Interval: Codable, Sendable, Equatable {
        var start: Date
        var end: Date
    }

    static let cacheName = "free-rooms"

    /// Whether this describes the day it is being read on.
    func covers(_ date: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: date)
    }

    /// Rooms with nothing booked between `date` and `minutes` later.
    ///
    /// The half-hour default is the question actually being asked: not "is it
    /// empty this second" but "can I sit down and get something done".
    func free(at date: Date, forNext minutes: Int = 30) -> [Room] {
        let until = date.addingTimeInterval(TimeInterval(minutes * 60))
        return rooms
            .filter { room in
                room.busy.allSatisfy { $0.end <= date || $0.start >= until }
            }
            .sorted { $0.name < $1.name }
    }
}

nonisolated extension FreeRoomsSnapshot {
    /// The campuses a snapshot has been written for.
    ///
    /// The widget's configuration has to offer a choice before it has ever
    /// rendered anything, and an extension cannot enumerate the store. A tiny
    /// list in the shared defaults is enough, and it is the app — which knows
    /// the real catalogue — that keeps it current.
    private static let campusesKey = "knownCampuses"

    static var knownCampuses: [String] {
        get { SharedAccount.defaults.stringArray(forKey: campusesKey) ?? [] }
        set { SharedAccount.defaults.set(newValue, forKey: campusesKey) }
    }

    /// The campus the app last wrote a snapshot for.
    ///
    /// What an unconfigured widget shows. The catalogue's first campus is
    /// alphabetical, not the one the student uses, and usually has no data.
    private static let lastCampusKey = "lastFreeRoomsCampus"

    static var lastCampus: String? {
        get { SharedAccount.defaults.string(forKey: lastCampusKey) }
        set { SharedAccount.defaults.set(newValue, forKey: lastCampusKey) }
    }
}

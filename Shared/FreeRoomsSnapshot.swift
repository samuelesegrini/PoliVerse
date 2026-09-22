import Foundation

/// One day's room bookings for one campus, flattened to what a widget can use.
///
/// The widget does no networking. Bookings for a day are fetched once and do not
/// change during it, so the app writes the busy intervals here and the widget
/// answers “free now” by comparing them against the clock at render time —
/// see ``free(at:forNext:)``.
///
/// Stored under ``cacheName`` in ``OfflineStore``.
nonisolated struct FreeRoomsSnapshot: Codable, Sendable, Equatable {
    /// The day these bookings describe.
    ///
    /// A snapshot from another day answers a different question rather than answering
    /// this one staly, which is what ``covers(_:)`` is checked for.
    var day: Date
    /// The campus, as the room catalogue names it.
    var campus: String
    /// Every room on the campus, with its bookings for the day.
    var rooms: [Room]

    /// One room and when it is taken.
    nonisolated struct Room: Codable, Sendable, Equatable, Identifiable {
        /// The room's identifier in the catalogue.
        var id: String
        /// The room's name as it is signposted.
        var name: String
        /// The building it is in, when known.
        var building: String?
        /// Seating capacity, when known.
        var seats: Int?
        /// When the room is taken, in order. Any time outside these is free.
        var busy: [Interval]
    }

    /// A half-open span during which a room is taken.
    ///
    /// Stored as two dates rather than as a `DateInterval`, whose decoder traps when
    /// `end` precedes `start` — which a cache file is exactly where a malformed pair
    /// can arrive from.
    nonisolated struct Interval: Codable, Sendable, Equatable {
        /// When the booking begins.
        var start: Date
        /// When the booking ends.
        var end: Date
    }

    /// The record name this snapshot is stored under in the shared store.
    static let cacheName = "free-rooms"

    /// Whether this snapshot describes the day a given date falls on.
    ///
    /// - Parameter date: Usually the moment the widget is rendering.
    /// - Returns: `true` when ``day`` is the same calendar day.
    func covers(_ date: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: date)
    }

    /// Rooms with nothing booked over a window starting at a given moment.
    ///
    /// - Parameters:
    ///   - date: When the window starts.
    ///   - minutes: How long the window is. The default half hour matches the question
    ///     being asked — somewhere to sit down and work, not a room empty for one
    ///     second.
    /// - Returns: The free rooms, sorted by name.
    func free(at date: Date, forNext minutes: Int = 30) -> [Room] {
        let until = date.addingTimeInterval(TimeInterval(minutes * 60))
        return rooms
            .filter { room in
                room.busy.allSatisfy { $0.end <= date || $0.start >= until }
            }
            .sorted { $0.name < $1.name }
    }
}

/// The small pieces of state the widget's configuration needs before the widget
/// has ever rendered, kept in the shared defaults.
///
/// An extension cannot enumerate the shared store, so the app — which knows the
/// real catalogue — writes these.
nonisolated extension FreeRoomsSnapshot {
    /// Shared-defaults key for ``knownCampuses``.
    private static let campusesKey = "knownCampuses"

    /// The campuses a snapshot has been written for, offered as the widget's
    /// configuration choices. Empty until the app has written one.
    static var knownCampuses: [String] {
        get { SharedAccount.defaults.stringArray(forKey: campusesKey) ?? [] }
        set { SharedAccount.defaults.set(newValue, forKey: campusesKey) }
    }

    /// Shared-defaults key for ``lastCampus``.
    private static let lastCampusKey = "lastFreeRoomsCampus"

    /// The campus the app last wrote a snapshot for, and what an unconfigured widget
    /// shows.
    ///
    /// Preferred over the catalogue's first campus, which is alphabetical rather than
    /// the one the student attends.
    static var lastCampus: String? {
        get { SharedAccount.defaults.string(forKey: lastCampusKey) }
        set { SharedAccount.defaults.set(newValue, forKey: lastCampusKey) }
    }
}

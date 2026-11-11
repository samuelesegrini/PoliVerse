import Foundation

/// When the answer to "which rooms are free now" next changes.
///
/// A room's bookings for the day are known once fetched, so whether it is free
/// changes only at known instants: when a booking ends, and, since "free now"
/// means free for the next half hour, half an hour before one starts. Between two
/// such instants nothing on screen can change, so nothing is recomputed and
/// nothing is asked: the app sleeps until the next one.
nonisolated enum BoundaryClock {
    /// How far ahead a room must stay free to count as free now, in seconds.
    static let lead: TimeInterval = 1800

    /// The instants at which a room's "free now" answer can change.
    ///
    /// - Parameters:
    ///   - bookings: The room's bookings.
    ///   - lead: How far ahead a room must stay free to count as free.
    static func boundaries(of bookings: [RoomBooking], lead: TimeInterval = lead) -> [Date] {
        bookings.flatMap { [$0.start.addingTimeInterval(-lead), $0.end] }
    }

    /// The next instant after `now` at which any room's answer changes.
    ///
    /// - Parameters:
    ///   - now: The current time.
    ///   - rooms: The rooms held, with their bookings.
    ///   - lead: How far ahead a room must stay free to count as free.
    /// - Returns: The instant, or `nil` when nothing changes any more today.
    static func next(after now: Date, in rooms: [RoomSchedule], lead: TimeInterval = lead) -> Date? {
        rooms.lazy.flatMap { boundaries(of: $0.bookings, lead: lead) }.filter { $0 > now }.min()
    }

    /// The rooms whose answer changes at an instant: the ones worth asking about
    /// again when it passes.
    ///
    /// - Parameters:
    ///   - boundary: The instant.
    ///   - rooms: The rooms held.
    ///   - lead: How far ahead a room must stay free to count as free.
    /// - Returns: Their ids.
    static func rooms(changingAt boundary: Date, in rooms: [RoomSchedule], lead: TimeInterval = lead) -> [String] {
        rooms.filter { room in
            boundaries(of: room.bookings, lead: lead).contains { abs($0.timeIntervalSince(boundary)) < 1 }
        }.map(\.id)
    }
}

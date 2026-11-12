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

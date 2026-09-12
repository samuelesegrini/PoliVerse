import ActivityKit
import Foundation

/// The "sto andando a lezione" Live Activity.
///
/// Shared because both processes need it: the app starts and ends the
/// activity, the widget extension draws it. `ActivityAttributes` is matched by
/// type identity across the two, so a copy in each target would not be the
/// same activity.
nonisolated struct LectureActivityAttributes: ActivityAttributes {
    /// Fixed for the life of the activity — a lecture does not change its name
    /// while you walk to it.
    var title: String
    var room: String?
    var building: String?
    var start: Date
    var end: Date

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var phase: Phase

        /// Where the lecture is in its own life.
        ///
        /// Stored rather than derived from the clock, because the *system*
        /// redraws the activity at times it chooses, and a view that computed
        /// the phase itself would flip between "fra poco" and "in corso" only
        /// when iOS happened to look. The app schedules the transitions.
        nonisolated enum Phase: String, Codable, Hashable, Sendable {
            /// Not started yet: the countdown is to `start`.
            case upcoming
            /// Under way: the countdown is to `end`.
            case running
            /// Over. Kept briefly so the activity can say so before it goes.
            case ended
        }
    }

    /// The countdown a given phase is about.
    func deadline(for phase: ContentState.Phase) -> Date {
        switch phase {
        case .upcoming: start
        case .running, .ended: end
        }
    }

    var location: String? {
        switch (room, building) {
        case let (room?, building?) where room != building: "\(room) · \(building)"
        case let (room?, _): room
        case let (_, building?): building
        default: nil
        }
    }
}

import ActivityKit
import Foundation

/// The attributes of the lecture Live Activity.
///
/// Shared between targets because both processes need it: the app starts, updates
/// and ends the activity through ``LiveActivityController``, and the widget
/// extension draws it in ``LectureLiveActivity``. `ActivityAttributes` are matched
/// by type identity across processes, so a copy per target would not be the same
/// activity.
nonisolated struct LectureActivityAttributes: ActivityAttributes {
    /// What the activity is following.
    ///
    /// Lectures and exams share the machinery — both are a named thing in a
    /// room between two times — but not the words or the colour: "in corso"
    /// reads differently for a lecture you may be late to and for an exam you
    /// are sitting.
    nonisolated enum Kind: String, Codable, Hashable, Sendable {
        /// A timetabled lecture, laboratory or tutorial.
        case lecture
        /// An exam sitting.
        case exam
    }

    /// Whether this is a lecture or an exam. Fixed for the life of the
    /// activity.
    ///
    /// Defaulted, so an activity started by an older build — whose encoded
    /// attributes carry no `kind` — still decodes, as a lecture.
    var kind: Kind = .lecture
    /// The lecture's or sitting's name. Fixed for the life of the activity.
    var title: String
    /// The room, when known.
    var room: String?
    /// The building, when known.
    var building: String?
    /// When the lecture begins.
    var start: Date
    /// When the lecture ends.
    var end: Date

    /// The part of the activity that changes while it is live.
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// Where the lecture is in its own course.
        var phase: Phase

        /// Where the lecture stands relative to the clock.
        ///
        /// Stored rather than derived at render time: the system redraws an activity when
        /// it chooses, so a view that computed the phase itself would change it only when
        /// iOS happened to look. The app schedules the transitions.
        nonisolated enum Phase: String, Codable, Hashable, Sendable {
            /// Not started. The countdown runs to ``LectureActivityAttributes/start``.
            case upcoming
            /// Under way. The countdown runs to ``LectureActivityAttributes/end``.
            case running
            /// Over. Held briefly so the activity can say so before it is dismissed.
            case ended
        }
    }

    /// The date a phase's countdown runs to.
    ///
    /// - Parameter phase: The phase being drawn.
    /// - Returns: ``start`` for ``ContentState/Phase/upcoming``, ``end`` otherwise.
    func deadline(for phase: ContentState.Phase) -> Date {
        switch phase {
        case .upcoming: start
        case .running, .ended: end
        }
    }

    /// The SF Symbol the activity is drawn with.
    var symbol: String {
        switch kind {
        case .lecture: "person.bubble"
        case .exam: "pencil.and.list.clipboard"
        }
    }

    /// The room and building as one line — `"room · building"` when both are known and
    /// differ, whichever is known when only one is, `nil` when neither is.
    var location: String? {
        switch (room, building) {
        case let (room?, building?) where room != building: "\(room) · \(building)"
        case let (room?, _): room
        case let (_, building?): building
        default: nil
        }
    }
}

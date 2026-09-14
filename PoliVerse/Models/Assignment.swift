import Foundation

/// A WeBeep assignment deadline, as the reminders need it.
nonisolated struct AssignmentDeadline: Identifiable, Sendable, Equatable, Codable {
    let id: Int
    let courseCode: String
    let courseName: String
    let name: String
    let due: Date
}

/// New assignments and moved deadlines on WeBeep.
///
/// The same reading rules as the other WeBeep detectors: silent first
/// reading, an old snapshot is a new baseline, an empty answer keeps what was
/// known. It also hands back the deadlines ahead, which the reminders use.
///
/// Whether the student has already submitted is not known from this call.
/// `core_calendar_get_action_events_by_timesort` lists only work still to
/// hand in, in one request (§22), but is not verified on WeBeep yet; until it
/// is, reminding someone who has handed in is the smaller harm.
nonisolated enum AssignmentDetector {
    struct Result: Sendable {
        let updates: [ExamUpdate]
        let snapshot: MaterialSnapshot
        /// Every assignment with a deadline still ahead.
        let deadlines: [AssignmentDeadline]
    }

    static func detect(
        previous: MaterialSnapshot?, assignments: [MoodleAssignment], course: MaterialCourse, now: Date
    ) -> Result {
        let current = Dictionary(assignments.map { (key($0), version($0)) }, uniquingKeysWith: { first, _ in first })
        let deadlines = assignments.compactMap { assignment -> AssignmentDeadline? in
            guard let due = assignment.due, due > now else { return nil }
            return AssignmentDeadline(id: assignment.id, courseCode: course.code, courseName: course.name,
                                      name: assignment.name ?? "", due: due)
        }
        // What this answer says exists; an empty answer keeps what was known.
        let versions = assignments.isEmpty ? (previous?.versions ?? [:]) : current
        let snapshot = MaterialSnapshot(versions: versions, notable: [:], takenAt: now)

        guard let previous, now.timeIntervalSince(previous.takenAt) < MaterialChangeDetector.staleAfter else {
            return Result(updates: [], snapshot: snapshot, deadlines: deadlines)
        }

        var updates: [ExamUpdate] = []
        for assignment in assignments {
            // Only deadlines still ahead are news: one added, or moved, into
            // the past is nothing to act on.
            guard let due = assignment.due, due > now else { continue }
            let name = assignment.name ?? ""
            let evidence = "webeep:mod_assign_get_assignments course=\(course.moodleID) assign=\(assignment.id)"
            switch previous.versions[key(assignment)] {
            case nil:
                updates.append(update(.assignmentAdded, course: course, now: now, evidence: evidence,
                                      name: name, identity: "\(assignment.id)", due: due))
            case let old? where old != version(assignment):
                updates.append(update(.deadlineChanged, course: course, now: now, evidence: evidence,
                                      name: name, identity: "\(assignment.id)@\(version(assignment))",
                                      due: due, old: old))
            default:
                continue
            }
        }
        return Result(updates: updates, snapshot: snapshot, deadlines: deadlines)
    }

    /// Whether a moved deadline came earlier — the direction that costs time.
    static func movedEarlier(_ update: ExamUpdate) -> Bool {
        guard let old = update.oldValue.flatMap(TimeInterval.init), old > 0, let due = update.examDate else { return false }
        return due.timeIntervalSince1970 < old
    }

    /// The evening a reminder goes out: the one before the last full day.
    ///
    /// Moodle's usual deadline is 00:00, which means "by the end of the day
    /// before". Reminding the evening before 00:00 would be six hours ahead;
    /// the day that matters is the one ending then.
    static func reminderDay(for due: Date) -> Date {
        let lastMoment = due.addingTimeInterval(-60)
        return PoliMiDate.romeCalendar.date(byAdding: .day, value: -1, to: lastMoment) ?? lastMoment
    }

    private static func update(
        _ kind: ExamUpdate.Kind, course: MaterialCourse, now: Date, evidence: String,
        name: String, identity: String, due: Date, old: String? = nil
    ) -> ExamUpdate {
        ExamUpdate(
            kind: kind, examID: nil, courseCode: course.code, courseName: course.name,
            // Read straight off `duedate`.
            detectedAt: now, source: .webeep, confidence: .exact, evidence: evidence,
            oldValue: old, newValue: name, identity: identity,
            // The deadline travels as the date the update concerns.
            wasEnrolled: false, examDate: due)
    }

    private static func version(_ assignment: MoodleAssignment) -> String { String(assignment.duedate ?? 0) }
    static func key(_ assignment: MoodleAssignment) -> String { "assign:\(assignment.id)" }
    /// The log key of a course's assignments, for both snapshot and deadlines.
    static func courseKey(_ course: MaterialCourse) -> String { "assign-\(course.moodleID)" }
}

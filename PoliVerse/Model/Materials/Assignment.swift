import Foundation

/// A WeBeep assignment deadline, in the shape the reminders need.
nonisolated struct AssignmentDeadline: Identifiable, Sendable, Equatable, Codable {
    /// Moodle's assignment id.
    let id: Int
    /// The teaching code the assignment belongs to.
    let courseCode: String
    /// The teaching's name.
    let courseName: String
    /// The assignment's name.
    let name: String
    /// When it is due. Always in the future when it is published here.
    let due: Date
}

/// Notices new assignments and moved deadlines on WeBeep, and reports the deadlines
/// still ahead.
///
/// Reads by the same rules as the other WeBeep detectors: the first reading is silent,
/// a snapshot older than ``MaterialChangeDetector/staleAfter`` becomes a new baseline,
/// and an empty answer keeps what was already known rather than reporting everything
/// as removed.
///
/// Whether the student has already handed in is not known from this call, so a
/// reminder may reach someone who has — which is the smaller harm.
nonisolated enum AssignmentDetector {
    /// What one reading produced.
    struct Result: Sendable {
        /// What changed since the previous reading. Empty on a baseline reading.
        let updates: [ExamUpdate]
        /// The reading to compare the next one against.
        let snapshot: MaterialSnapshot
        /// Every assignment whose deadline is still ahead.
        let deadlines: [AssignmentDeadline]
    }

    /// Compares a course's assignments against the previous reading.
    ///
    /// Only deadlines still ahead are reported: one added or moved into the past is
    /// nothing to act on.
    ///
    /// - Parameters:
    ///   - previous: The last reading, or `nil` for the first.
    ///   - assignments: What Moodle answered.
    ///   - course: The course being read.
    ///   - now: The moment of this reading.
    /// - Returns: The updates, the new snapshot and the deadlines ahead.
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

    /// Whether a moved deadline came earlier, which is the direction that costs time.
    ///
    /// - Parameter update: A ``ExamUpdate/Kind/deadlineChanged`` update.
    /// - Returns: `true` when the new deadline precedes the old one.
    static func movedEarlier(_ update: ExamUpdate) -> Bool {
        guard let old = update.oldValue.flatMap(TimeInterval.init), old > 0, let due = update.examDate else { return false }
        return due.timeIntervalSince1970 < old
    }

    /// The day a reminder for a deadline should go out: the one before the last full day.
    ///
    /// Moodle's usual deadline is midnight, which means by the end of the day before, so
    /// reminding the evening before midnight would be several hours early.
    ///
    /// - Parameter due: When the assignment is due.
    /// - Returns: The day the reminder belongs to.
    static func reminderDay(for due: Date) -> Date {
        let lastMoment = due.addingTimeInterval(-60)
        return PoliMiDate.romeCalendar.date(byAdding: .day, value: -1, to: lastMoment) ?? lastMoment
    }

    /// Builds one assignment update.
    ///
    /// - Parameters:
    ///   - kind: What happened.
    ///   - course: The course it happened in.
    ///   - now: When it was noticed.
    ///   - evidence: The call and identifiers it was read from.
    ///   - name: The assignment's name.
    ///   - identity: What makes this update distinct from the next.
    ///   - due: The deadline, which travels as the date the update concerns.
    ///   - old: The previous deadline, for a change.
    /// - Returns: The update.
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

    /// What is compared between readings: the deadline, as epoch seconds.
    ///
    /// - Parameter assignment: The assignment.
    /// - Returns: The version string.
    private static func version(_ assignment: MoodleAssignment) -> String { String(assignment.duedate ?? 0) }
    /// The snapshot key for one assignment.
    ///
    /// - Parameter assignment: The assignment.
    /// - Returns: The key.
    static func key(_ assignment: MoodleAssignment) -> String { "assign:\(assignment.id)" }
    /// The record name a course's assignment snapshot and deadlines are stored under.
    ///
    /// - Parameter course: The course.
    /// - Returns: The record name.
    static func courseKey(_ course: MaterialCourse) -> String { "assign-\(course.moodleID)" }
}

import Foundation

/// Decides which exam updates interrupt the student, and how.
///
/// Importance comes from the kind of change, urgency from how soon the exam
/// is, and context from whether the student is even signed up. On top sit
/// three guards against notification fatigue: quiet hours, a daily budget for
/// anything short of urgent, and folding a burst into one summary.
///
/// Pure, like ``NotificationPlan``; the service around it only hands the
/// result to `UNUserNotificationCenter`. Table and rationale in
/// `docs/academic-intelligence-layer.md` §11.
nonisolated enum ExamUpdatePolicy {
    /// Ordinary pushes per day. Urgent ones do not count and are not capped:
    /// a published mark should never wait for tomorrow's allowance.
    static let dailyBudget = 3
    /// One ordinary push per course in this interval.
    static let courseInterval: TimeInterval = 3600
    /// More than this in one refresh becomes a single summary.
    static let burstLimit = 3
    /// A room is news for a sitting within this…
    static let roomHorizon: TimeInterval = 7 * 86400
    /// …and urgent within this.
    static let imminent: TimeInterval = 2 * 86400
    /// A results file concerns a sitting held at most this long ago.
    static let resultsWindow: TimeInterval = 60 * 86400
    /// An exam notice concerns a sitting at most this far ahead.
    static let noticeHorizon: TimeInterval = 14 * 86400

    static func decide(
        _ updates: [ExamUpdate],
        history: [ExamUpdate],
        preferences: NotificationPreferences,
        now: Date
    ) -> [ExamUpdate] {
        let isQuiet = preferences.isQuiet(hour: PoliMiDate.romeCalendar.component(.hour, from: now))
        var seen = history

        return updates.map { update in
            var decided = update
            // Off altogether, WeBeep off, or this course silenced (§11.3):
            // the feed only.
            guard preferences.examUpdates,
                  preferences.weBeepUpdates || update.source != .webeep,
                  !preferences.isMuted(code: update.courseCode, name: update.courseName) else {
                decided.delivery = .inApp
                return decided
            }

            var delivery = baseline(for: update, among: updates, history: history, now: now)
            if isQuiet, delivery == .push || delivery == .priority {
                delivery = .morning
            }
            delivery = budgeted(delivery, course: update.courseCode, history: seen, now: now)
            decided.delivery = delivery
            seen.append(decided)
            return decided
        }
    }

    /// Rations ordinary pushes: a few a day, one per course an hour. Anything
    /// above ordinary passes untouched.
    static func budgeted(
        _ delivery: ExamUpdate.Delivery, course: String, history: [ExamUpdate], now: Date
    ) -> ExamUpdate.Delivery {
        guard delivery == .push else { return delivery }
        let calendar = PoliMiDate.romeCalendar
        let pushes = history.filter { $0.delivery == .push }
        let today = pushes.filter { calendar.isDate($0.detectedAt, inSameDayAs: now) }.count
        let sameCourse = pushes.contains {
            $0.courseCode == course && now.timeIntervalSince($0.detectedAt) < courseInterval
        }
        return today >= dailyBudget || sameCourse ? .digest : .push
    }

    /// What an update deserves before quiet hours and budget have their say.
    private static func baseline(
        for update: ExamUpdate, among batch: [ExamUpdate], history: [ExamUpdate], now: Date
    ) -> ExamUpdate.Delivery {
        let untilExam = update.examDate.map { $0.timeIntervalSince(now) } ?? .infinity

        switch update.kind {
        case .gradePublished:
            return .urgent

        case .refusalOpened:
            // Arriving with its mark, it is the same notification.
            let withMark = batch.contains { $0.kind == .gradePublished && $0.examID == update.examID }
            return withMark ? .inApp : .urgent

        case .roomPublished, .roomChanged:
            // §11.2: only for a sitting the student is enrolled in, within
            // the week; imminent enough to pierce Focus inside two days. A
            // sitting already held can still have its room edited upstream,
            // and that is not worth anyone's attention.
            guard update.wasEnrolled, (0...roomHorizon).contains(untilExam) else { return .inApp }
            return untilExam <= imminent ? .urgent : .priority

        case .dateChanged, .withdrawn:
            return update.wasEnrolled ? .urgent : .inApp

        case .correctionsAvailable:
            // Not in the §11.2 table: worth knowing, never urgent — so the
            // one kind that is rationed.
            return .push

        case .enrolmentOpened:
            return .digest

        case .gradeRecorded:
            // The libretto catching up with a mark already announced. When it
            // was not, a join by course is not certain enough to push.
            let announced = (history + batch).contains {
                $0.kind == .gradePublished
                    && ($0.courseCode == update.courseCode || $0.courseName == update.courseName)
                    && now.timeIntervalSince($0.detectedAt) < ExamUpdateLog.retention
            }
            return announced ? .inApp : .digest

        case .discovered, .enrolled, .unenrolled:
            // The student did it, or will see it with the enrolment opening.
            return .inApp

        case .resultsPosted where update.lookup != nil:
            // The file was read. The student's own line is what matters —
            // unless the exam services already said it, or the file turned
            // out not to be a table of results at all (§10.3).
            guard let lookup = update.lookup, lookup.looksLikeResults || lookup.found else { return .inApp }
            if (history + batch).contains(where: { confirms($0, fileGrade: update) }) { return .inApp }
            // Found in a table of results: the student's own line. Found in
            // anything else is a mention, not a mark (§10.3).
            return lookup.found && lookup.looksLikeResults && !update.isReplacement ? .push : .digest

        case .resultsPosted:
            // §11.2: worth a push only right after a sitting the student was
            // enrolled in, and only for a name that says results plainly —
            // otherwise it is somebody else's results, a correction, or a
            // guess. §21: everything else from WeBeep is Bassa.
            let justSat = update.wasEnrolled && (-resultsWindow...0).contains(untilExam)
            let certain = update.confidence == .high && !update.isReplacement
            return justSat && certain ? .push : .digest

        case .solutionsPosted, .examNoticePosted:
            // Bassa: the evening summary, for a course with a sitting in
            // play; otherwise just the feed.
            return update.wasEnrolled ? .digest : .inApp

        case .materialAdded:
            return .inApp

        case .assignmentAdded:
            // The reminder the evening before does the urgent part.
            return .digest

        case .deadlineChanged:
            // §21 keeps WeBeep news Bassa. The one exception is a deadline
            // brought forward into the coming week: waiting for the evening
            // summary can cost the time that was taken away.
            let soon = (0...roomHorizon).contains(untilExam)
            return soon && AssignmentDetector.movedEarlier(update) ? .push : .digest

        case .announcementPosted:
            // §11.2 teacherCommunication: Media, and worth a push when it
            // talks about a sitting the student has in play (the detector
            // only gives it one then). Rationed like any ordinary push.
            return update.wasEnrolled ? .push : .digest
        }
    }

    /// Whether an official mark is the same fact as a mark read from a file:
    /// same course, the same sitting where both know one, and seen within the
    /// results window of each other — in either order.
    static func confirms(_ official: ExamUpdate, fileGrade file: ExamUpdate) -> Bool {
        guard official.kind == .gradePublished || official.kind == .gradeRecorded,
              official.courseCode == file.courseCode || official.courseName == file.courseName,
              abs(official.detectedAt.timeIntervalSince(file.detectedAt)) <= resultsWindow
        else { return false }
        guard let sitting = file.examDate, let officialSitting = official.examDate else { return true }
        return sitting == officialSitting
    }

    /// Delivered notifications an official mark makes obsolete: the "you are
    /// in the results" ones for the same course. Removed rather than left
    /// beside the new one — one notification per fact (§11.4).
    static func obsoleteNotificationIDs(for decided: [ExamUpdate], delivered: [String]) -> [String] {
        let courses = Set(decided.filter { $0.kind == .gradePublished || $0.kind == .gradeRecorded }.map(\.courseCode))
        return delivered.filter { id in
            courses.contains { id.hasPrefix("update-\(ExamUpdate.Kind.resultsPosted.rawValue)|\($0)|") }
        }
    }

    /// Notifications to deliver right away.
    static func notifications(for decided: [ExamUpdate], now: Date) -> [PlannedNotification] {
        let outgoing = decided.filter { $0.delivery.isImmediate }
        let urgent = outgoing.contains { $0.delivery == .urgent }

        guard outgoing.count <= burstLimit else {
            let courses = orderedUnique(outgoing.map(\.courseName))
            return [PlannedNotification(
                id: "update-burst-\(Int(now.timeIntervalSince1970))",
                kind: .update,
                title: String(localized: "\(outgoing.count) novità sui tuoi esami"),
                body: summary(courses),
                fireDate: now,
                isTimeSensitive: urgent,
                thread: "exam-updates",
                relevance: 1)]
        }

        return outgoing.map { update in
            let refusable = update.kind == .gradePublished
                && decided.contains { $0.kind == .refusalOpened && $0.examID == update.examID }
            // A mark read from a file stays in the app: it is unconfirmed, and
            // a lock screen is not private.
            let shown = update.lookup?.found == true ? String(localized: "Apri l'app per vederlo") : update.detail
            let detail = [update.courseName, shown,
                          refusable ? String(localized: "Puoi rifiutarlo") : nil]
                .compactMap { $0 }
                .joined(separator: " · ")
            return PlannedNotification(
                id: "update-\(update.id)",
                kind: .update,
                title: update.title,
                body: detail,
                fireDate: now,
                isTimeSensitive: update.delivery == .urgent,
                thread: update.examID.map { "exam-\($0)" } ?? "course-\(update.courseCode)",
                // §11.2: Alta leads a summary, Media follows.
                relevance: update.delivery == .push ? 0.6 : 1)
        }
    }

    /// Summaries still to come: one each evening for what could wait, one
    /// each morning for what was held back overnight.
    ///
    /// Derived from the log rather than remembered: an update's slot follows
    /// from when it was seen. Rebuilding the plan therefore never loses or
    /// duplicates a summary.
    static func digests(from log: [ExamUpdate], now: Date, preferences: NotificationPreferences) -> [PlannedNotification] {
        let held = log.compactMap { update -> (Date, ExamUpdate)? in
            switch update.delivery {
            case .digest:
                // The evening summary waits out quiet hours too, if the
                // student's start before 18:00 (§11.3).
                let evening = next(NotificationPlan.eveningHour, after: update.detectedAt)
                return preferences.isQuiet(hour: NotificationPlan.eveningHour)
                    ? (next(preferences.quietUntil, after: evening), update)
                    : (evening, update)
            case .morning:
                return (next(preferences.quietUntil, after: update.detectedAt), update)
            default:
                return nil
            }
        }
        let bySlot = Dictionary(grouping: held, by: \.0)

        return bySlot
            .filter { $0.key > now }
            .sorted { $0.key < $1.key }
            .map { fire, entries in
                let ordered = entries.map(\.1).sorted { $0.detectedAt < $1.detectedAt }
                let lines = ordered.map { String(localized: "\($0.title): \($0.courseName)") }
                return PlannedNotification(
                    id: "update-digest-\(Int(fire.timeIntervalSince1970))",
                    kind: .update,
                    title: String(localized: "Novità sui tuoi esami"),
                    body: summary(orderedUnique(lines)),
                    fireDate: fire,
                    isTimeSensitive: false,
                    thread: "exam-updates",
                    relevance: 0.2)
            }
    }

    /// The next `hour`:00 in Rome strictly after `date`.
    private static func next(_ hour: Int, after date: Date) -> Date {
        let today = PoliMiDate.time(hour, on: date)
        if date < today { return today }
        let tomorrow = PoliMiDate.romeCalendar.date(byAdding: .day, value: 1, to: date) ?? date
        return PoliMiDate.time(hour, on: tomorrow)
    }

    private static func summary(_ lines: [String]) -> String {
        let shown = lines.prefix(burstLimit).joined(separator: "\n")
        let rest = lines.count - burstLimit
        return rest > 0 ? shown + "\n" + String(localized: "e altre \(rest)") : shown
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

/// The updates the app has seen for one account, and the snapshot they were
/// computed against.
///
/// Stored through ``OfflineStore`` under the matricola, so a career switch
/// neither mixes two students' histories nor announces the other career's
/// sittings as new.
nonisolated struct ExamUpdateLog: Sendable, Equatable, Codable {
    static let name = "exam-updates"
    /// Long enough to cover a session and its results; short enough that the
    /// file never grows into something worth thinking about.
    static let retention: TimeInterval = 180 * 86400
    static let cap = 300
    /// The same change seen again within this is the same sighting — a
    /// foreground load and a background refresh racing. Later, it is news:
    /// a room can go A→B→A→B.
    static let dedupWindow: TimeInterval = 3600

    var state: ExamWatchState?
    /// Each WeBeep course's last listing, by Moodle course id.
    var materials: [String: MaterialSnapshot]?
    /// When the student last opened the full feed. Kept with the log, so it
    /// belongs to the account and goes when the account's data does.
    var seenAt: Date?
    /// Deadlines ahead, per Moodle course id, for the reminders.
    var deadlines: [String: [AssignmentDeadline]]?
    /// Newest first.
    var updates: [ExamUpdate] = []

    /// Updates not already in the log, in the order given.
    func unseen(_ candidates: [ExamUpdate]) -> [ExamUpdate] {
        var accepted: [ExamUpdate] = []
        for candidate in candidates {
            let duplicate = (updates + accepted).contains {
                $0.id == candidate.id
                    && abs(candidate.detectedAt.timeIntervalSince($0.detectedAt)) < Self.dedupWindow
            }
            if !duplicate { accepted.append(candidate) }
        }
        return accepted
    }

    /// Adds what is new, advances the snapshot, and trims.
    ///
    /// - Returns: the updates actually added.
    @discardableResult
    mutating func record(_ candidates: [ExamUpdate], state: ExamWatchState, now: Date) -> [ExamUpdate] {
        let added = unseen(candidates)
        self.state = state
        let cutoff = now.addingTimeInterval(-Self.retention)
        // A course page not read in the retention period is a course no
        // longer followed; its listing goes too.
        materials = materials?.filter { $0.value.takenAt >= cutoff }
        // Deadlines past, or of a course not read for a fortnight — hidden,
        // rotated out, last year's — would remind about work that may no
        // longer exist.
        deadlines = deadlines?
            .filter { key, _ in
                (materials?[key]?.takenAt).map { now.timeIntervalSince($0) < MaterialChangeDetector.staleAfter } ?? false
            }
            .mapValues { $0.filter { $0.due > now } }
            .filter { !$0.value.isEmpty }
        updates = Array(
            (added.reversed() + updates)
                .filter { $0.detectedAt >= cutoff }
                .sorted { $0.detectedAt > $1.detectedAt }
                .prefix(Self.cap))
        return added
    }
}

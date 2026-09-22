import Foundation

/// Decides which exam updates interrupt the student, and how.
///
/// Importance comes from the kind of change, urgency from how soon the sitting is, and
/// context from whether the student is even enrolled. Three guards against notification
/// fatigue sit on top: quiet hours, a daily budget for anything short of urgent, and
/// folding a burst into one summary.
///
/// Pure, like ``NotificationPlan``: ``NotificationModel`` only hands the result to the
/// system. The table and its rationale are in
/// `docs/academic-intelligence-layer.md` §11.
nonisolated enum ExamUpdatePolicy {
    /// How many ordinary pushes a day. Urgent ones neither count nor are capped: a
    /// published mark should not wait for tomorrow's allowance.
    static let dailyBudget = 3
    /// How long one course must wait between ordinary pushes.
    static let courseInterval: TimeInterval = 3600
    /// More immediate notifications than this in one pass become a single summary. Also how
    /// many lines a summary lists before counting the rest.
    static let burstLimit = 3
    /// How soon a sitting must be for its room to be news. Also the window in which a
    /// deadline brought forward is pushed.
    static let roomHorizon: TimeInterval = 7 * 86400
    /// How soon a sitting must be for its room to be allowed through Focus.
    static let imminent: TimeInterval = 2 * 86400
    /// How long after a sitting a results file can still be taken to concern it. Also how
    /// far apart an official mark and one read from a file may be and still be the same
    /// fact.
    static let resultsWindow: TimeInterval = 60 * 86400
    /// How far ahead a sitting can be for an exam notice to be taken to concern it.
    static let noticeHorizon: TimeInterval = 14 * 86400

    /// Decides the delivery of each update in a pass.
    ///
    /// An update is left at ``ExamUpdate/Delivery/inApp`` when exam updates are off, when
    /// it came from WeBeep and WeBeep updates are off, when its category is switched off, or
    /// when its course is muted. Otherwise a baseline is chosen from the kind, demoted to
    /// ``ExamUpdate/Delivery/morning`` during quiet hours, and then rationed.
    ///
    /// Updates decided earlier in the same pass count towards the budget of those after
    /// them.
    ///
    /// - Parameters:
    ///   - updates: The pass's updates, in the order they were found.
    ///   - history: What has already been delivered, from the log.
    ///   - preferences: What the student has asked for.
    ///   - now: The moment of this pass.
    /// - Returns: The same updates with their delivery set.
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
                  preferences.isEnabled(update.kind.category),
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

    /// Rations ordinary pushes: ``dailyBudget`` a day, and one per course per
    /// ``courseInterval``. Anything above ordinary passes through untouched.
    ///
    /// - Parameters:
    ///   - delivery: The delivery chosen so far.
    ///   - course: The teaching code, for the per-course limit.
    ///   - history: What has already been delivered.
    ///   - now: The moment of this pass.
    /// - Returns: The delivery, demoted to ``ExamUpdate/Delivery/digest`` when a limit is
    ///   reached.
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

    /// What an update deserves before quiet hours and the budget have their say.
    ///
    /// A published mark is urgent. A refusal window is urgent unless the mark arrives with
    /// it, in which case they are one notification. A room is news only for a sitting the
    /// student is enrolled in within ``roomHorizon``, and pierces Focus within
    /// ``imminent``. A moved or withdrawn sitting is urgent only for someone enrolled.
    ///
    /// Everything read from WeBeep stays low: a results file is pushed only just after a
    /// sitting the student sat and only when its name says results plainly, an announcement
    /// only when it names a sitting in play, and a deadline only when it was brought
    /// forward into the coming week.
    ///
    /// A mark read out of a file is not pushed when the exam services have already said it,
    /// nor when the file turned out not to be a table of results.
    ///
    /// - Parameters:
    ///   - update: The update to judge.
    ///   - batch: The rest of this pass, for updates that pair up.
    ///   - history: What has already been delivered.
    ///   - now: The moment of this pass.
    /// - Returns: The baseline delivery.
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

    /// Whether an official mark is the same fact as a mark read out of a file.
    ///
    /// Same teaching, the same sitting where both know one, and seen within
    /// ``resultsWindow`` of each other in either order.
    ///
    /// - Parameters:
    ///   - official: A published or recorded mark.
    ///   - file: A results file the app read.
    /// - Returns: `true` when the two describe one fact.
    static func confirms(_ official: ExamUpdate, fileGrade file: ExamUpdate) -> Bool {
        guard official.kind == .gradePublished || official.kind == .gradeRecorded,
              official.courseCode == file.courseCode || official.courseName == file.courseName,
              abs(official.detectedAt.timeIntervalSince(file.detectedAt)) <= resultsWindow
        else { return false }
        guard let sitting = file.examDate, let officialSitting = official.examDate else { return true }
        return sitting == officialSitting
    }

    /// Delivered notifications an official mark makes obsolete: the results-file ones for
    /// the same teaching.
    ///
    /// Withdrawn rather than left beside the new one — one notification per fact.
    ///
    /// - Parameters:
    ///   - decided: This pass's updates, with their deliveries set.
    ///   - delivered: The identifiers currently in Notification Centre.
    /// - Returns: The identifiers to withdraw.
    static func obsoleteNotificationIDs(for decided: [ExamUpdate], delivered: [String]) -> [String] {
        let courses = Set(decided.filter { $0.kind == .gradePublished || $0.kind == .gradeRecorded }.map(\.courseCode))
        return delivered.filter { id in
            courses.contains { id.hasPrefix("update-\(ExamUpdate.Kind.resultsPosted.rawValue)|\($0)|") }
        }
    }

    /// The notifications to deliver right away.
    ///
    /// More than ``burstLimit`` of them become a single summary. A mark read out of a file
    /// is not put on the Lock Screen — it is unconfirmed, and a Lock Screen is not private —
    /// so the notification says to open the app instead.
    ///
    /// - Parameters:
    ///   - decided: This pass's updates, with their deliveries set.
    ///   - now: The moment to deliver at.
    /// - Returns: The notifications.
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

    /// The summaries still to come: one each evening for what could wait, one each morning
    /// for what quiet hours held back.
    ///
    /// Derived from the log rather than remembered, since an update's slot follows from when
    /// it was seen — so rebuilding the plan never loses or duplicates a summary. An evening
    /// summary whose hour falls inside quiet hours waits them out too.
    ///
    /// - Parameters:
    ///   - log: Every update the app has recorded.
    ///   - now: The moment to plan from. Slots already past are dropped.
    ///   - preferences: The student's chosen summary hour and quiet hours.
    /// - Returns: One notification per slot, soonest first.
    static func digests(from log: [ExamUpdate], now: Date, preferences: NotificationPreferences) -> [PlannedNotification] {
        let held = log.compactMap { update -> (Date, ExamUpdate)? in
            switch update.delivery {
            case .digest:
                // The summary waits out quiet hours too, when the student's
                // chosen hour falls inside them (§11.3).
                let evening = next(preferences.digestHour, after: update.detectedAt)
                return preferences.isQuiet(hour: preferences.digestHour)
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

    /// The next occurrence of a given hour in Rome, strictly after a date.
    ///
    /// - Parameters:
    ///   - hour: The hour of day.
    ///   - date: The moment to search from.
    /// - Returns: That hour today when it is still ahead, and tomorrow otherwise.
    private static func next(_ hour: Int, after date: Date) -> Date {
        let today = PoliMiDate.time(hour, on: date)
        if date < today { return today }
        let tomorrow = PoliMiDate.romeCalendar.date(byAdding: .day, value: 1, to: date) ?? date
        return PoliMiDate.time(hour, on: tomorrow)
    }

    /// Joins lines into a summary body, listing at most ``burstLimit`` and counting the
    /// rest.
    ///
    /// - Parameter lines: The lines to show.
    /// - Returns: The body.
    private static func summary(_ lines: [String]) -> String {
        let shown = lines.prefix(burstLimit).joined(separator: "\n")
        let rest = lines.count - burstLimit
        return rest > 0 ? shown + "\n" + String(localized: "e altre \(rest)") : shown
    }

    /// Removes duplicates while keeping the first occurrence's position.
    ///
    /// - Parameter values: The values to filter.
    /// - Returns: The distinct values, in order.
    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

/// The updates the app has recorded for one account, and the readings they were computed
/// against.
///
/// Stored through ``OfflineStore`` under the matricola, so a career switch neither mixes
/// two students' histories nor announces the other career's sittings as new.
///
/// ``record(_:state:now:)`` is what advances it: it rejects duplicates, trims to
/// ``retention`` and ``cap``, and drops the readings and deadlines of course pages no
/// longer followed.
nonisolated struct ExamUpdateLog: Sendable, Equatable, Codable {
    /// The offline record name the log is stored under.
    static let name = "exam-updates"
    /// How long an update is kept: long enough to cover a session and its results, short
    /// enough that the file stays small.
    static let retention: TimeInterval = 180 * 86400
    /// How many updates are kept at most, newest first.
    static let cap = 300
    /// Within this, the same change seen again is the same sighting — a foreground load and
    /// a background refresh racing. Beyond it, it is news: a room can move back and forth.
    static let dedupWindow: TimeInterval = 3600

    /// The last reading of the exam services and the libretto.
    var state: ExamWatchState?
    /// Each WeBeep course's last listing, by Moodle course id.
    var materials: [String: MaterialSnapshot]?
    /// When the student last opened the full feed.
    ///
    /// Kept with the log, so it belongs to the account and goes when the account's data
    /// does.
    var seenAt: Date?
    /// The deadlines still ahead, per Moodle course id, for the reminders.
    var deadlines: [String: [AssignmentDeadline]]?
    /// The recorded updates, newest first.
    var updates: [ExamUpdate] = []

    /// The candidates not already in the log, in the order given.
    ///
    /// A candidate matching a recorded update within ``dedupWindow`` is rejected, as is a
    /// second copy within the same call.
    ///
    /// - Parameter candidates: The updates a pass found.
    /// - Returns: The ones worth recording.
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

    /// Adds what is new, advances the reading, and trims.
    ///
    /// Listings not read within ``MaterialChangeDetector/staleAfter`` are dropped, as are
    /// their deadlines: a course page not read for a fortnight is one no longer followed —
    /// hidden, rotated out, or last year's — and reminding about its work would be reminding
    /// about work that may no longer exist. Deadlines already past are dropped too.
    ///
    /// - Parameters:
    ///   - candidates: The updates a pass found.
    ///   - state: The reading they were computed against.
    ///   - now: The moment of this pass.
    /// - Returns: The updates actually added.
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

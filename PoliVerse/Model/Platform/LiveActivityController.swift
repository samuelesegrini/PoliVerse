import ActivityKit
import Foundation
import Observation
import OSLog

/// Starts, advances and ends the lecture Live Activity.
///
/// Started only when the student asks. An activity that began by itself for every
/// lecture would put something on the Lock Screen nobody requested, and starting one
/// from the background needs a push server this app does not have.
///
/// One activity at a time: ``start(for:)`` ends any other first. While the app is
/// running, ``scheduleAdvance(for:)`` moves the activity through its phases and
/// dismisses it a few minutes after the lecture ends; a suspended app runs no code, so
/// the activity's own `staleDate` is what dims it in the meantime.
@Observable
final class LiveActivityController {
    /// The agenda entry currently on the Lock Screen, or `nil` when none is.
    private(set) var currentEventID: Int?
    /// Why starting failed, when it did. The setting that governs Live Activities is
    /// buried, so “nothing happened” would be a poor answer.
    private(set) var errorMessage: String?

    /// The running activity's identifier.
    ///
    /// The activity is found by id rather than held: `Activity` is not `Sendable`, so a
    /// stored one belongs to this object's isolation region and could not be handed to the
    /// `async` calls that update or end it.
    private var activityID: String?

    /// The running activity, looked up by ``activityID``, or `nil` when none is running.
    private var activity: Activity<LectureActivityAttributes>? {
        guard let activityID else { return nil }
        return Activity<LectureActivityAttributes>.activities
            .first { $0.id == activityID }
    }
    /// The task moving the activity through its phases.
    private var advance: Task<Void, Never>?
    /// Diagnostic log for this type, under the `liveactivity` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "liveactivity")

    /// Whether the system will accept an activity at all. `false` when the student has
    /// switched Live Activities off for this app, which is a setting rather than an error.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Whether an entry is the one currently on the Lock Screen.
    ///
    /// - Parameter event: The agenda entry to check.
    /// - Returns: `true` when it is showing.
    func isShowing(_ event: AgendaEvent) -> Bool { currentEventID == event.id }

    /// Whether a sitting is the one currently on the Lock Screen.
    ///
    /// - Parameter exam: The sitting to check.
    /// - Returns: `true` when it is showing.
    func isShowing(_ exam: ExamSession) -> Bool { currentEventID == Self.eventID(of: exam) }

    /// Starts the activity for one lecture, ending any other first.
    ///
    /// The activity's `staleDate` is the lecture's end, so the system dims it rather than
    /// continuing to show a confident countdown past the moment it describes. A refusal —
    /// the feature disabled, or too many activities running — sets ``errorMessage``.
    ///
    /// - Parameter event: The lecture to follow. Use ``canStart(_:at:)`` to decide whether
    ///   to offer it.
    func start(for event: AgendaEvent) {
        guard isAvailable else {
            errorMessage = String(localized: "Le attività in tempo reale sono disattivate per PoliVerse.")
            return
        }
        // One at a time: two lectures live at once is never what was meant,
        // and the second would bury the first.
        end()

        let attributes = LectureActivityAttributes(
            kind: event.kind == .exam ? .exam : .lecture,
            title: event.title,
            room: event.roomLabel,
            building: event.calendarName,
            start: event.start,
            end: event.end)
        let phase = Self.phase(of: event, at: .now)

        do {
            let started = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: .init(phase: phase),
                    // Past the end the figures stop meaning anything, so the
                    // system is told to grey it out rather than keep showing a
                    // confident countdown to a moment that has passed.
                    staleDate: event.end),
                // The app may never run again before the lecture ends — the
                // phone stays in a pocket for two hours. Handing iOS the
                // dismissal up front means the activity still clears itself.
                pushType: nil)
            activityID = started.id
            currentEventID = event.id
            errorMessage = nil
            scheduleAdvance(for: event)
            log.notice("live activity started for event \(event.id, privacy: .public)")
        } catch {
            // `ActivityAuthorizationError` covers the honest cases — too many
            // activities, or the feature disabled between the check and here.
            errorMessage = error.localizedDescription
            log.error("live activity refused: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Starts the activity for one exam sitting.
    ///
    /// A sitting carries a start and no end, so the activity runs for
    /// ``ExamCalendarEvent/defaultLength`` — the same three hours the calendar
    /// export assumes. The student sees a countdown to the exam and then one
    /// to the hour it is expected to finish, which is what an exam morning is
    /// actually spent watching.
    ///
    /// - Parameter exam: The sitting to follow. Use ``canStart(_:at:)`` to
    ///   decide whether to offer it.
    func start(for exam: ExamSession) {
        guard let event = Self.event(for: exam) else { return }
        start(for: event)
        // ``start(for:)`` filed it under the synthesised entry's id, which is
        // the one ``isShowing(_:)`` looks for.
        currentEventID = event.id
    }

    /// The agenda entry a sitting stands in for.
    ///
    /// The activity speaks one language — a named thing in a room between two
    /// times — so a sitting is translated into it once, here, rather than the
    /// activity learning about sittings.
    ///
    /// - Parameter exam: The sitting.
    /// - Returns: The entry, or `nil` when the sitting has no date and so
    ///   nothing to count down to.
    nonisolated static func event(for exam: ExamSession) -> AgendaEvent? {
        guard let date = exam.date else { return nil }
        return AgendaEvent(
            id: eventID(of: exam),
            title: [exam.courseName, exam.kind?.isEmpty == false ? exam.kind : nil]
                .compactMap { $0 }.joined(separator: " · "),
            start: date,
            end: date.addingTimeInterval(ExamCalendarEvent.defaultLength),
            kind: .exam,
            room: exam.room)
    }

    /// The identity a sitting's activity is filed under.
    ///
    /// Negated so it cannot collide with an agenda entry's own id: the two
    /// come from different services, and one is not the other.
    ///
    /// - Parameter exam: The sitting.
    /// - Returns: The identity.
    nonisolated static func eventID(of exam: ExamSession) -> Int { -exam.id }

    /// Dismisses the activity immediately and stops advancing it. Does nothing when none
    /// is running.
    func end() {
        advance?.cancel()
        advance = nil
        guard let id = activityID else { return }
        activityID = nil
        currentEventID = nil
        Task { await Self.endActivity(id) }
    }

    /// Moves the activity to ``LectureActivityAttributes/ContentState/Phase/running`` at
    /// the lecture's start and to `ended` at its end, then dismisses it five minutes later.
    ///
    /// Best effort: a suspended app runs no code, so a lecture that begins while the phone
    /// is in a pocket keeps its previous phase until the app runs again. The countdown text
    /// is live either way, and `staleDate` dims the activity once the lecture is over.
    ///
    /// - Parameter event: The lecture being followed.
    private func scheduleAdvance(for event: AgendaEvent) {
        advance?.cancel()
        advance = Task { [weak self] in
            for phase in [LectureActivityAttributes.ContentState.Phase.running, .ended] {
                let moment = phase == .running ? event.start : event.end
                let wait = moment.timeIntervalSinceNow
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                if Task.isCancelled { return }
                await self?.update(to: phase, end: event.end)
            }
            // A few minutes of "finita" so the transition is visible, then
            // out of the way.
            try? await Task.sleep(for: .seconds(300))
            if Task.isCancelled { return }
            self?.end()
        }
    }

    /// Moves the running activity to a phase.
    ///
    /// - Parameters:
    ///   - phase: The phase to show.
    ///   - end: The lecture's end, which becomes the content's stale date.
    private func update(to phase: LectureActivityAttributes.ContentState.Phase, end: Date) async {
        guard let id = activityID else { return }
        await Self.updateActivity(id, to: phase, staleAfter: end)
    }

    // ActivityKit's calls are `nonisolated async` and `Activity` is not
    // `Sendable`, so a value looked up on the main actor cannot be handed to
    // them. Doing both the lookup and the call outside any actor keeps the
    // value in one region and needs no unsafe opt-out.

    /// Dismisses an activity by id, outside any actor.
    ///
    /// ActivityKit's calls are `nonisolated async` and `Activity` is not `Sendable`, so
    /// both the lookup and the call happen here, keeping the value in one isolation region.
    ///
    /// - Parameter id: The activity to dismiss.
    private nonisolated static func endActivity(_ id: String) async {
        guard let live = Activity<LectureActivityAttributes>.activities
            .first(where: { $0.id == id }) else { return }
        await live.end(nil, dismissalPolicy: .immediate)
    }

    /// Updates an activity by id, outside any actor, for the same reason as
    /// ``endActivity(_:)``.
    ///
    /// - Parameters:
    ///   - id: The activity to update.
    ///   - phase: The phase to show.
    ///   - end: The content's stale date.
    private nonisolated static func updateActivity(
        _ id: String,
        to phase: LectureActivityAttributes.ContentState.Phase,
        staleAfter end: Date
    ) async {
        guard let live = Activity<LectureActivityAttributes>.activities
            .first(where: { $0.id == id }) else { return }
        await live.update(
            ActivityContent(state: .init(phase: phase), staleDate: end))
    }

    /// Which phase an entry is in at a given moment.
    ///
    /// - Parameters:
    ///   - event: The agenda entry.
    ///   - date: The moment to judge at.
    /// - Returns: The phase.
    nonisolated static func phase(
        of event: AgendaEvent, at date: Date
    ) -> LectureActivityAttributes.ContentState.Phase {
        if date < event.start { return .upcoming }
        if date < event.end { return .running }
        return .ended
    }

    /// Whether offering the activity makes sense for an entry.
    ///
    /// Lectures and exams, still to end, and starting inside the kind's own
    /// window: four hours for a lecture, which is a thing you walk to, and
    /// twelve for an exam, which is a thing a whole morning is arranged
    /// around. A deadline is neither — it is an instant, with nothing to
    /// count down through.
    ///
    /// - Parameters:
    ///   - event: The agenda entry.
    ///   - date: The moment to judge at.
    /// - Returns: `true` when the activity is worth offering.
    nonisolated static func canStart(_ event: AgendaEvent, at date: Date = .now) -> Bool {
        let window: TimeInterval
        switch event.kind {
        case .lecture: window = 4 * 3600
        case .exam: window = 12 * 3600
        default: return false
        }
        return event.end > date && event.start.timeIntervalSince(date) < window
    }

    /// Whether offering the activity makes sense for a sitting.
    ///
    /// - Parameters:
    ///   - exam: The sitting.
    ///   - date: The moment to judge at.
    /// - Returns: `true` when the activity is worth offering.
    nonisolated static func canStart(_ exam: ExamSession, at date: Date = .now) -> Bool {
        guard let event = event(for: exam) else { return false }
        return canStart(event, at: date)
    }
}

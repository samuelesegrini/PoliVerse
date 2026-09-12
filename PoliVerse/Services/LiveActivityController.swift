import ActivityKit
import Foundation
import Observation
import OSLog

/// Starts, advances and ends the lecture Live Activity.
///
/// Deliberately manual. A Live Activity that started itself for every lecture
/// would put something on the Lock Screen the student never asked for, and
/// starting one from the background is not possible without a push server
/// this app does not have. The student taps "sto andando"; that is the signal.
@Observable
final class LiveActivityController {
    private(set) var currentEventID: Int?
    /// Why starting failed, when it did — the setting that governs this is
    /// buried and "nothing happened" is a bad answer.
    private(set) var errorMessage: String?

    /// The activity is found by id rather than held.
    ///
    /// `Activity` is not `Sendable`, so a stored one belongs to this object's
    /// isolation region and cannot be handed to the `async` calls that end or
    /// update it. Looking it up produces a fresh value each time, which can.
    private var activityID: String?

    private var activity: Activity<LectureActivityAttributes>? {
        guard let activityID else { return nil }
        return Activity<LectureActivityAttributes>.activities
            .first { $0.id == activityID }
    }
    private var advance: Task<Void, Never>?
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "liveactivity")

    /// Whether the system will accept one at all. False when the student has
    /// switched Live Activities off for this app, which is a setting, not an
    /// error.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Whether this event is the one currently on the Lock Screen.
    func isShowing(_ event: AgendaEvent) -> Bool { currentEventID == event.id }

    func start(for event: AgendaEvent) {
        guard isAvailable else {
            errorMessage = String(localized: "Le attività in tempo reale sono disattivate per PoliVerse.")
            return
        }
        // One at a time: two lectures live at once is never what was meant,
        // and the second would bury the first.
        end()

        let attributes = LectureActivityAttributes(
            title: event.title,
            room: event.room ?? event.roomAcronym,
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

    func end() {
        advance?.cancel()
        advance = nil
        guard let id = activityID else { return }
        activityID = nil
        currentEventID = nil
        Task { await Self.endActivity(id) }
    }

    /// Moves the activity through its phases while the app is running.
    ///
    /// Best effort, and only that: a suspended app runs no code, so a lecture
    /// that starts while the phone is in a pocket keeps saying "inizia tra"
    /// with a countdown that has passed zero. The visible damage is small
    /// because the timer text is live either way, and `staleDate` makes the
    /// system dim it once the lecture is over. Fixing it properly needs push
    /// tokens and a server, which this app deliberately does not have.
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

    private func update(to phase: LectureActivityAttributes.ContentState.Phase, end: Date) async {
        guard let id = activityID else { return }
        await Self.updateActivity(id, to: phase, staleAfter: end)
    }

    // ActivityKit's calls are `nonisolated async` and `Activity` is not
    // `Sendable`, so a value looked up on the main actor cannot be handed to
    // them. Doing both the lookup and the call outside any actor keeps the
    // value in one region and needs no unsafe opt-out.

    private nonisolated static func endActivity(_ id: String) async {
        guard let live = Activity<LectureActivityAttributes>.activities
            .first(where: { $0.id == id }) else { return }
        await live.end(nil, dismissalPolicy: .immediate)
    }

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

    /// Which phase an event is in at a given moment.
    nonisolated static func phase(
        of event: AgendaEvent, at date: Date
    ) -> LectureActivityAttributes.ContentState.Phase {
        if date < event.start { return .upcoming }
        if date < event.end { return .running }
        return .ended
    }

    /// Whether offering the activity makes sense for this entry.
    ///
    /// Only lectures, and only ones that have not finished: a Live Activity
    /// counting down to something already over is noise, and an exam or a
    /// deadline is not something you walk to for two hours.
    nonisolated static func canStart(_ event: AgendaEvent, at date: Date = .now) -> Bool {
        event.kind == .lecture
            && event.end > date
            && event.start.timeIntervalSince(date) < 4 * 3600
    }
}

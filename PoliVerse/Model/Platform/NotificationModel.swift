import Foundation
import Observation
import OSLog
import UserNotifications

/// Schedules and delivers the reminders ``NotificationPlan`` decides on.
///
/// Everything is local. The app has no push infrastructure and no server, which means
/// reminders keep working offline and no timetable leaves the device to make them
/// happen.
///
/// ``reschedule(events:exams:assignments:updates:)`` replaces the whole pending plan,
/// and ``deliver(_:)`` pushes exam news immediately, outside that plan.
@Observable
final class NotificationModel {
    /// What the system says about permission, refreshed by ``refreshAuthorization()``.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// The plan currently pending, as last scheduled.
    private(set) var scheduled: [PlannedNotification] = []

    /// Which reminders the student wants and how far ahead. Persisted whenever it
    /// changes.
    var preferences: NotificationPreferences = .stored {
        didSet {
            guard preferences != oldValue else { return }
            preferences.store()
        }
    }

    /// The system notification centre.
    private let centre = UNUserNotificationCenter.current()
    /// Diagnostic log for this type, under the `notifications` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "notifications")

    /// The category every reminder carries.
    static let categoryIdentifier = "segrini.samuele.PoliVerse.reminder"

    /// Re-reads ``authorization`` from the system.
    func refreshAuthorization() async {
        authorization = await centre.notificationSettings().authorizationStatus
    }

    /// Asks for permission to show alerts, play sounds and badge the icon.
    ///
    /// Asks once: the system remembers a refusal, so the interface sends the student to
    /// Settings instead of asking again.
    ///
    /// - Returns: `true` when permission was granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await centre.requestAuthorization(
                options: [.alert, .sound, .badge])
            await refreshAuthorization()
            log.notice("Notification authorization: \(granted, privacy: .public)")
            return granted
        } catch {
            log.error("Notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Replaces every pending reminder with the current plan.
    ///
    /// Replaced rather than added to: lectures move and sittings are withdrawn, and a
    /// reminder for something that no longer exists cannot be noticed from inside the app.
    /// Each reminder fires on Rome wall-clock components, so a plan made in one time zone
    /// still fires at the right local moment.
    ///
    /// Does nothing without permission.
    ///
    /// - Parameters:
    ///   - events: The agenda entries to remind about.
    ///   - exams: The exam sittings.
    ///   - assignments: The assignment deadlines.
    ///   - updates: The exam updates worth a planned reminder.
    func reschedule(events: [AgendaEvent], exams: [ExamSession], assignments: [AssignmentDeadline] = [],
                    updates: [ExamUpdate] = []) async {
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }

        let plan = NotificationPlan.build(
            events: events, exams: exams, assignments: assignments, updates: updates, preferences: preferences)

        centre.removeAllPendingNotificationRequests()
        for item in plan {
            let components = PoliMiDate.romeCalendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: item.fireDate)
            await add(item, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        }

        scheduled = plan
        let byKind = Dictionary(grouping: plan, by: \.kind)
            .map { "\($0.key.rawValue) \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        log.notice("Scheduled \(plan.count, privacy: .public) reminders (\(byKind, privacy: .public))")
    }

    /// Delivers the exam updates the policy chose to push, at once.
    ///
    /// Kept out of ``reschedule(events:exams:assignments:updates:)`` because these are
    /// news rather than reminders for a moment: they are added with no trigger, so
    /// rebuilding the pending plan afterwards cannot cancel them. Notifications the policy
    /// has since superseded are withdrawn first.
    ///
    /// Does nothing without permission.
    ///
    /// - Parameter decided: The updates to push.
    func deliver(_ decided: [ExamUpdate]) async {
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }
        let delivered = await centre.deliveredNotifications().map(\.request.identifier)
        let obsolete = ExamUpdatePolicy.obsoleteNotificationIDs(for: decided, delivered: delivered)
        if !obsolete.isEmpty { centre.removeDeliveredNotifications(withIdentifiers: obsolete) }
        let immediate = ExamUpdatePolicy.notifications(for: decided, now: .now)
        for item in immediate { await add(item, trigger: nil) }
        if !immediate.isEmpty {
            log.notice("Delivered \(immediate.count, privacy: .public) exam update notifications")
        }
    }

    /// Adds one notification request.
    ///
    /// Only genuinely imminent reminders are marked time-sensitive, since marking
    /// everything urgent is how an app gets silenced altogether. A failure is logged and
    /// otherwise ignored.
    ///
    /// - Parameters:
    ///   - item: What to show.
    ///   - trigger: When to show it, or `nil` to deliver immediately.
    private func add(_ item: PlannedNotification, trigger: UNNotificationTrigger?) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = item.thread ?? item.kind.rawValue
        content.userInfo = ["kind": item.kind.rawValue]
        // Only what is genuinely imminent pierces Focus. Marking
        // everything urgent is how an app gets silenced altogether.
        content.interruptionLevel = item.isTimeSensitive ? .timeSensitive : .active
        if let relevance = item.relevance { content.relevanceScore = relevance }

        let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
        do {
            try await centre.add(request)
        } catch {
            log.error("Could not schedule \(item.id, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Cancels every pending reminder, on sign-out or when the student turns reminders
    /// off.
    func cancelAll() {
        centre.removeAllPendingNotificationRequests()
        scheduled = []
        log.notice("Cancelled all reminders")
    }

    /// The screen a tapped reminder should open.
    ///
    /// - Parameter kind: The raw ``PlannedNotification/Kind`` carried on the notification.
    /// - Returns: The calendar for lectures and deadlines, the career for exams,
    ///   enrolment windows and updates, and Oggi for anything unrecognised.
    static func destination(for kind: String) -> AppDestination {
        switch PlannedNotification.Kind(rawValue: kind) {
        case .lecture, .deadline: .calendar
        case .exam, .enrolment, .update: .career
        case nil: .home
        }
    }
}

/// Routes a tapped reminder to the right screen, and decides how one arriving while
/// the app is open is presented.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    /// Sends the tapped reminder's destination through ``AppDestination/send()``.
    ///
    /// - Parameters:
    ///   - center: The notification centre.
    ///   - response: What the student tapped.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let kind = response.notification.request.content.userInfo["kind"] as? String ?? ""
        await MainActor.run { NotificationModel.destination(for: kind).send() }
    }

    /// Shows a reminder as a banner even with the app open: a lecture starting in fifteen
    /// minutes is worth interrupting whatever screen is in front of the student.
    ///
    /// - Parameters:
    ///   - center: The notification centre.
    ///   - notification: The reminder about to be presented.
    /// - Returns: Banner, sound and notification-centre listing.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

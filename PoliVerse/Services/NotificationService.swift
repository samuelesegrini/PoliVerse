import Foundation
import Observation
import OSLog
import UserNotifications

/// Schedules the reminders ``NotificationPlan`` decides on.
///
/// Everything is local. The app has no push infrastructure and no server of
/// its own, which is a feature here: reminders keep working offline, and no
/// timetable leaves the device to make them happen.
@Observable
final class NotificationService {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var scheduled: [PlannedNotification] = []

    var preferences: NotificationPreferences = .stored {
        didSet {
            guard preferences != oldValue else { return }
            preferences.store()
        }
    }

    private let centre = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "notifications")

    /// Tapping a reminder should land on the right screen, not just open the
    /// app, so each kind carries the tab it belongs to.
    static let categoryIdentifier = "one.wape.PoliVerse.reminder"

    func refreshAuthorization() async {
        authorization = await centre.notificationSettings().authorizationStatus
    }

    /// Asks, once. A refusal is remembered by the system, so asking again is
    /// pointless — the UI sends the user to Settings instead.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await centre.requestAuthorization(
                options: [.alert, .sound, .badge, .timeSensitive])
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
    /// Replace rather than add: the timetable changes, lectures move, exams
    /// are withdrawn. Adding would leave a reminder for a lecture that no
    /// longer exists, and there is no way to notice that from inside the app.
    func reschedule(events: [AgendaEvent], exams: [ExamSession], updates: [ExamUpdate] = []) async {
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }

        let plan = NotificationPlan.build(
            events: events, exams: exams, updates: updates, preferences: preferences)

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

    /// Delivers exam updates the policy chose to push, right away.
    ///
    /// Not part of ``reschedule``: these are not planned for a moment, they
    /// are news, and a nil trigger delivers them at once — so rebuilding the
    /// pending plan afterwards cannot cancel them.
    func deliver(_ decided: [ExamUpdate]) async {
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }
        let immediate = ExamUpdatePolicy.notifications(for: decided, now: .now)
        for item in immediate { await add(item, trigger: nil) }
        if !immediate.isEmpty {
            log.notice("Delivered \(immediate.count, privacy: .public) exam update notifications")
        }
    }

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

    /// Drops everything — on sign-out, or when the user turns reminders off.
    func cancelAll() {
        centre.removeAllPendingNotificationRequests()
        scheduled = []
        log.notice("Cancelled all reminders")
    }

    /// The tab a reminder should open.
    static func destination(for kind: String) -> AppDestination {
        switch PlannedNotification.Kind(rawValue: kind) {
        case .lecture, .deadline: .calendar
        case .exam, .enrolment, .update: .career
        case nil: .home
        }
    }
}

/// Routes a tapped reminder to the right tab.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let kind = response.notification.request.content.userInfo["kind"] as? String ?? ""
        await MainActor.run { NotificationService.destination(for: kind).send() }
    }

    /// Shown even with the app open: a lecture starting in fifteen minutes is
    /// worth interrupting whatever screen is in front of the user.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

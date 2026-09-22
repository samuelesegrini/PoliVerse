import SwiftUI

/// What the app does around ``RootView``: land every way in from outside,
/// and keep Spotlight and the reminders in step with the data.
struct AppShellDuties: ViewModifier {
    /// Opens a destination in the interface on screen.
    let route: (AppDestination) -> Void

    /// Whether the app is on screen, in the foreground or in the background.
    @Environment(\.scenePhase) private var scenePhase
    /// The shared ``CourseModel``, from the environment.
    @Environment(CourseModel.self) private var courses
    /// The shared ``RoomsModel``, from the environment.
    @Environment(RoomsModel.self) private var rooms
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``UpdateFeed``, from the environment.
    @Environment(UpdateFeed.self) private var feed
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``NotificationModel``, from the environment.
    @Environment(NotificationModel.self) private var notifications
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    @State private var spotlight = SpotlightIndex()

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        content
            // Remote pictures load through a session with a cache of their own.
            .asyncImageURLSession(ImageSession.shared)
            // Every way in from outside — Siri, Shortcuts, Spotlight's action
            // row — arrives as one notification, so the routing exists once.
            .onReceive(NotificationCenter.default.publisher(for: AppDestination.notification)) {
                guard let raw = $0.object as? String,
                      let destination = AppDestination(rawValue: raw) else { return }
                route(destination)
            }
            // A Control Center button runs its intent in the widget extension,
            // where the notification above reaches nobody. The destination is
            // left in the shared container instead and collected here, once
            // the app is actually in front of the user.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let destination = AppDestination.takePending()
                else { return }
                route(destination)
            }
            .task {
                // Launching *because* of a control: the phase is already active
                // by the time the view appears, so the change above never fires.
                if let destination = AppDestination.takePending() { route(destination) }
            }
            // Indexed after the data lands, and only then: an index built from
            // an empty model would publish nothing and look like a broken
            // feature.
            .task(id: indexKey) {
                guard !session.useMockData, !courses.courses.isEmpty else { return }
                spotlight.index(
                    courses: courses.courses,
                    rooms: rooms.rooms,
                    teachers: Teacher.roster(courses: courses.courses, sessions: career.sessions),
                    exams: career.sessions)
                // The same material, in the narrow shape an App Intent can read
                // from a process where none of these services exist.
                EntityIndexWriter.write(courses: courses.courses, rooms: rooms.rooms,
                                        exams: career.sessions,
                                        account: session.student?.matricola)
            }
            // The Watch has no session and no network of its own, so the phone
            // hands it the day. Sent on the same signal the reminders use,
            // because it answers the same question: what has actually changed
            // in the timetable and the sittings.
            .task(id: watchKey) {
                guard !session.useMockData else { return }
                let figures = session.student.flatMap {
                    OfflineStore.shared.load(CareerSnapshot.self,
                                             as: CareerSnapshot.cacheName,
                                             account: $0.matricola)?.value
                }
                WatchBridge.shared.send(WatchSnapshotBuilder.build(
                    events: agenda.events, exams: career.sessions, day: .now, career: figures))
            }
            // Reminders follow the timetable: lectures move and exams are
            // withdrawn, and a reminder for a lecture that no longer exists is
            // invisible from inside the app.
            .task(id: reminderKey) {
                guard !session.useMockData else { return }
                await notifications.reschedule(
                    events: agenda.events, exams: career.sessions, assignments: feed.deadlines, updates: feed.updates)
            }
    }

    /// Rebuilt when the day, the timetable or the sittings change.
    ///
    /// The day is in the key because the Watch is sent one day at a time: past
    /// midnight the same events describe yesterday.
    private var watchKey: String {
        let day = PoliMiDate.romeCalendar.startOfDay(for: .now).timeIntervalSince1970
        return "\(day)-\(agenda.events.count)-\(career.sessions.count)"
    }

    /// Rebuilt when the timetable or the sittings change.
    private var reminderKey: String {
        "\(agenda.events.count)-\(career.sessions.count)-\(feed.updates.first?.id ?? "")-\(feed.deadlines.map { "\($0.id)@\($0.due.timeIntervalSince1970)" }.joined(separator: ","))-\(agenda.loadedRange?.upperBound.timeIntervalSince1970 ?? 0)"
    }

    /// Re-indexes when the material actually changes, rather than on every
    /// appearance.
    private var indexKey: String {
        "\(courses.courses.count)-\(rooms.rooms.count)-\(career.sessions.count)-\(session.student?.matricola ?? "")"
    }
}

/// Attaching the shell's duties to a view.
extension View {
    /// Applies ``AppShellDuties``.
    ///
    /// - Parameter route: Opens a destination in the interface on screen.
    /// - Returns: The view with the shell's duties attached.
    func appShellDuties(route: @escaping (AppDestination) -> Void) -> some View {
        modifier(AppShellDuties(route: route))
    }
}

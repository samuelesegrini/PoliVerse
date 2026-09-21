import SwiftUI

/// What the app does around ``RootView``: land every way in from outside,
/// and keep Spotlight and the reminders in step with the data.
struct AppShellDuties: ViewModifier {
    /// Opens a destination in the interface on screen.
    let route: (AppDestination) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(CourseModel.self) private var courses
    @Environment(RoomsModel.self) private var rooms
    @Environment(CareerModel.self) private var career
    @Environment(UpdateFeed.self) private var feed
    @Environment(Session.self) private var session
    @Environment(NotificationModel.self) private var notifications
    @Environment(AgendaModel.self) private var agenda
    @State private var spotlight = SpotlightIndex()

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

extension View {
    func appShellDuties(route: @escaping (AppDestination) -> Void) -> some View {
        modifier(AppShellDuties(route: route))
    }
}

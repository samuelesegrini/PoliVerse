import SwiftUI

/// Routes between login and the tab bar, and adapts to iPad width.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(OnboardingState.self) private var onboarding

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            // The first run explains the app before asking for an account, so
            // it owns the sign-in rather than sitting in front of it. Once it
            // has been through, a signed-out session is someone who already
            // knows what this is — switching career, or coming back — and
            // gets the plain login screen instead.
            case .signedOut, .failed, .exchangingCode:
                if onboarding.isComplete { LoginView() } else { OnboardingView() }
            case .signedIn:
                if onboarding.isComplete { MainTabView() } else { OnboardingView() }
            }
        }
        .task {
            await session.restore()
            // After the restore, not before: a token in the Keychain is what
            // says this install predates the onboarding.
            if session.student != nil { onboarding.adoptExistingInstall() }
        }
    }
}

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    /// One place every way in from outside lands: Siri, Shortcuts, Spotlight's
    /// action row, and Control Center.
    private func route(to destination: AppDestination) {
        switch destination {
        case .calendar: selection = "calendar"
        case .career, .plan, .simulator: selection = "career"
        case .weBeep: selection = "webeep"
        case .search, .freeRooms, .map: selection = "search"
        case .home: selection = "home"
        }
    }

    @Environment(CourseService.self) private var courses
    @Environment(RoomsService.self) private var rooms
    @Environment(CareerService.self) private var career
    @Environment(UpdateFeed.self) private var feed
    @Environment(Session.self) private var session

    @State private var selection = "home"
    @State private var spotlight = SpotlightIndex()
    @Environment(NotificationService.self) private var notifications
    @Environment(AgendaService.self) private var agenda

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "graduationcap", value: "home") { HomeView() }
            Tab("WeBeep", systemImage: "books.vertical", value: "webeep") { WeBeepView() }
            Tab("Calendario", systemImage: "calendar", value: "calendar") { CalendarView() }
            Tab("Carriera", systemImage: "chart.bar", value: "career") { CareerView() }
            Tab("Cerca", systemImage: "magnifyingglass", value: "search", role: .search) {
                SearchView()
            }
        }
        // Above the tabs rather than on one screen: sample data replaces
        // every one of them, so saying it once on the Home would leave the
        // libretto looking like a real libretto.
        .safeAreaInset(edge: .top, spacing: 0) { DemoModeBanner() }
        // Every way in from outside — Siri, Shortcuts, Spotlight's action row
        // — arrives as one notification, so the routing exists once.
        .onReceive(NotificationCenter.default.publisher(for: AppDestination.notification)) {
            guard let raw = $0.object as? String,
                  let destination = AppDestination(rawValue: raw) else { return }
            route(to: destination)
        }
        // A Control Center button runs its intent in the widget extension,
        // where the notification above reaches nobody. The destination is left
        // in the shared container instead and collected here, once the app is
        // actually in front of the user.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let destination = AppDestination.takePending()
            else { return }
            route(to: destination)
        }
        .task {
            // Launching *because* of a control: the phase is already active by
            // the time the view appears, so the change above never fires.
            if let destination = AppDestination.takePending() { route(to: destination) }
        }
        // Indexed after the data lands, and only then: an index built from an
        // empty model would publish nothing and look like a broken feature.
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

    /// Re-indexes when the material actually changes, rather than on every
    /// appearance.
    /// Rebuilt when the timetable or the sittings change.
    private var reminderKey: String {
        "\(agenda.events.count)-\(career.sessions.count)-\(feed.updates.first?.id ?? "")-\(feed.deadlines.map { "\($0.id)@\($0.due.timeIntervalSince1970)" }.joined(separator: ","))-\(agenda.loadedRange?.upperBound.timeIntervalSince1970 ?? 0)"
    }

    private var indexKey: String {
        "\(courses.courses.count)-\(rooms.rooms.count)-\(career.sessions.count)-\(session.student?.matricola ?? "")"
    }
}

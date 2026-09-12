import SwiftUI

/// Routes between login and the tab bar, and adapts to iPad width.
struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut, .failed, .exchangingCode:
                LoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .task { await session.restore() }
    }
}

struct MainTabView: View {
    @Environment(CourseService.self) private var courses
    @Environment(RoomsService.self) private var rooms
    @Environment(CareerService.self) private var career
    @Environment(Session.self) private var session

    @State private var selection = "home"
    @State private var spotlight = SpotlightIndex()

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
        // Every way in from outside — Siri, Shortcuts, Spotlight's action row
        // — arrives as one notification, so the routing exists once.
        .onReceive(NotificationCenter.default.publisher(for: AppDestination.notification)) {
            guard let raw = $0.object as? String,
                  let destination = AppDestination(rawValue: raw) else { return }
            switch destination {
            case .calendar: selection = "calendar"
            case .career, .plan, .simulator: selection = "career"
            case .weBeep: selection = "webeep"
            case .search, .freeRooms, .map: selection = "search"
            case .home: selection = "home"
            }
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
    }

    /// Re-indexes when the material actually changes, rather than on every
    /// appearance.
    private var indexKey: String {
        "\(courses.courses.count)-\(rooms.rooms.count)-\(career.sessions.count)-\(session.student?.matricola ?? "")"
    }
}

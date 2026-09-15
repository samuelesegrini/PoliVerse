import SwiftUI

/// The restructured app shell being tried out, in the layout the student
/// chose: four tabs instead of five, or a single page with a bottom panel.
///
/// Oggi merges the old Home and Calendario, since both show the same lessons
/// and exams filtered differently. Corsi replaces the WeBeep tab and the Home
/// course grid. Cerca is the system search tab. See
/// `docs/information-architecture.md`.
///
/// Not wired into the app yet: it lives only in previews until the structure
/// settles.
struct NewRootView: View {
    enum Destination: Hashable {
        case today, courses, career, search
    }

    @State private var selection: Destination = .today
    @AppStorage(AppLayout.storageKey) private var layout: AppLayout = .tabs
    @Environment(AgendaService.self) private var agenda
    /// Re-read every minute so the accessory moves on when a lesson ends.
    @State private var now = Date.now

    private var current: CurrentClass? {
        #if DEBUG
        // `-NowDemo` shows a lesson in progress without an account.
        if CommandLine.arguments.contains("-NowDemo") {
            return CurrentClass(event: AgendaEvent(
                id: -1, title: "Ingegneria del Software", start: now.addingTimeInterval(-40 * 60),
                end: now.addingTimeInterval(65 * 60), kind: .lecture, room: "Aula B.3.2",
                roomAcronym: nil, calendarName: nil), isOngoing: true)
        }
        #endif
        return CurrentClass.pick(from: agenda.events, now: now)
    }

    var body: some View {
        switch layout {
        case .singlePage: SinglePageHome()
        case .tabs: tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Oggi", systemImage: "calendar.day.timeline.left", value: .today) {
                TodayTab()
            }
            Tab("Corsi", systemImage: "books.vertical", value: .courses) {
                CoursesTab()
            }
            Tab("Carriera", systemImage: "graduationcap", value: .career) {
                CareerTab()
            }
            Tab(value: .search, role: .search) {
                SearchTab()
            }
        }
        // Above the tab bar while there is a class today, like Music's player.
        .currentClassAccessory(current)
        .task { await agenda.load(around: .now) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = .now
            }
        }
        // Selecting the search tab opens its field straight away.
        .tabViewSearchActivation(.searchTabSelection)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview("Nuova struttura") {
    NewRootView().previewEnvironment()
}

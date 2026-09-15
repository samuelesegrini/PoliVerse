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
    @State private var shell = ShellState()
    @AppStorage(AppLayout.storageKey) private var layout: AppLayout = .tabs
    @Environment(AgendaService.self) private var agenda
    /// Re-read every minute so the accessory moves on when a lesson ends.
    @State private var now = Date.now

    private var current: CurrentClass? { CurrentClass.forAccessory(from: agenda.events, now: now) }

    var body: some View {
        ZStack {
            switch layout {
            case .singlePage:
                SinglePageHome()
                    .transition(BlurReplaceTransition(configuration: .downUp).combined(with: ScaleTransition(0.96)))
            case .tabs:
                tabs
                    .transition(BlurReplaceTransition(configuration: .downUp).combined(with: ScaleTransition(0.96)))
            }
        }
        // The setting is written from Impostazioni: animate here, where the
        // change lands.
        .animation(.smooth(duration: 0.45), value: layout)
        .environment(\.shell, shell)
        .sheet(isPresented: $shell.showingSettings) { SettingsSheet() }
        .sheet(isPresented: $shell.showingProfile) {
            NavigationStack {
                ProfileView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { shell.showingProfile = false }
                        }
                    }
            }
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

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
    /// The layout on screen. Trails the stored setting so a change made in
    /// Impostazioni first closes the sheet, then animates.
    @State private var shownLayout: AppLayout?
    @State private var layoutChangePending = false
    @Environment(AgendaService.self) private var agenda
    /// Re-read every minute so the accessory moves on when a lesson ends.
    @State private var now = Date.now

    private var current: CurrentClass? { CurrentClass.forAccessory(from: agenda.events, now: now) }

    var body: some View {
        ZStack {
            switch shownLayout ?? layout {
            case .singlePage:
                SinglePageHome()
                    .transition(BlurReplaceTransition(configuration: .downUp).combined(with: ScaleTransition(0.96)))
            case .tabs:
                tabs
                    .transition(BlurReplaceTransition(configuration: .downUp).combined(with: ScaleTransition(0.96)))
            }
        }
        .onAppear { if shownLayout == nil { shownLayout = layout } }
        .onChange(of: layout) { _, new in
            if shell.showingSettings {
                layoutChangePending = true
                shell.showingSettings = false
            } else {
                withAnimation(.smooth(duration: 0.45)) { shownLayout = new }
            }
        }
        .overlay {
            if shell.isCustomizing {
                CustomizeOggi()
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .environment(\.shell, shell)
        .sheet(isPresented: $shell.showingSettings, onDismiss: {
            if shell.customizePending {
                shell.customizePending = false
                selection = .today
                withAnimation(.smooth(duration: 0.4)) { shell.isCustomizing = true }
            }
            guard layoutChangePending else { return }
            layoutChangePending = false
            withAnimation(.smooth(duration: 0.45)) { shownLayout = layout }
        }) { SettingsSheet() }
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

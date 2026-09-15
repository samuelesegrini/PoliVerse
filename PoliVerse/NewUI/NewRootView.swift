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
    @State private var layoutChangePending = false
    @Environment(AgendaService.self) private var agenda
    /// Re-read every minute so the accessory moves on when a lesson ends.
    @State private var now = Date.now

    private var current: CurrentClass? { CurrentClass.forAccessory(from: agenda.events, now: now) }

    var body: some View {
        // One tree for both layouts. Swapping two whole screens cross-faded
        // two navigation bars, two pages and a tab bar at once; here the page
        // and its bar stay put and only the bottom changes — the tab bar
        // slides away as the panel rises, and back.
        ZStack {
            // The ground the shrunk app and the gallery sit on.
            Color(.secondarySystemBackground).ignoresSafeArea()

            tabs
                // Personalizza, like the Lock Screen: the whole app scales
                // down into the gallery's middle card, and back up on close.
                .clipShape(.rect(cornerRadius: shell.customizeStage == .off ? 0 : 48))
                .shadow(color: .black.opacity(shell.customizeStage == .off ? 0 : 0.18), radius: 24, y: 10)
                .scaleEffect(shell.customizeStage == .off ? 1 : CustomizeOggi.cardScale)
                .allowsHitTesting(shell.customizeStage == .off)
                .ignoresSafeArea()

            if shell.customizeStage == .gallery {
                CustomizeOggi()
                    .transition(.opacity)
            }
        }
        .onChange(of: shell.isCustomizing) { _, customizing in
            customizing ? openCustomize() : closeCustomize()
        }
        .onAppear { shell.singlePage = layout == .singlePage }
        .onChange(of: layout) { _, new in
            if shell.showingSettings {
                layoutChangePending = true
                shell.showingSettings = false
            } else {
                show(new)
            }
        }
        .sheet(isPresented: $shell.showingSettings, onDismiss: {
            guard layoutChangePending else { return }
            layoutChangePending = false
            show(layout)
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
        // Outermost, so the sheets see the same shell as the page. Placed
        // before them, the sheets fell back to the default instance: the
        // settings sheet wrote to a stray copy and its dismissal never
        // found the pending change.
        .environment(\.shell, shell)
    }

    /// The layout on screen trails the stored setting, so a change made in
    /// Impostazioni first closes the sheet, then animates.
    private func show(_ layout: AppLayout) {
        if layout == .singlePage { selection = .today }
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) {
            shell.singlePage = layout == .singlePage
        }
    }

    private func openCustomize() {
        selection = .today
        withAnimation(.spring(duration: 0.45, bounce: 0.1)) {
            shell.customizeStage = .shrunk
        } completion: {
            withAnimation(.easeOut(duration: 0.2)) { shell.customizeStage = .gallery }
        }
    }

    private func closeCustomize() {
        withAnimation(.easeIn(duration: 0.15)) {
            shell.customizeStage = .shrunk
        } completion: {
            withAnimation(.spring(duration: 0.45, bounce: 0.1)) { shell.customizeStage = .off }
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
        .currentClassAccessory(shell.singlePage ? nil : current)
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

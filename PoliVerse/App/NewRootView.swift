import SwiftUI

/// The restructured app shell, in the layout the student chose: four tabs
/// instead of five, or a single page with a bottom panel.
///
/// Oggi merges the old Home and Calendario's day, since both show the same
/// lessons and exams filtered differently; the full calendar lives in Cerca.
/// Corsi replaces the WeBeep tab and the Home course grid. Both layouts reach
/// the same places, listed once in ``NewDestination``. See
/// `docs/information-architecture.md`.
struct NewRootView: View {
    @State private var shell = ShellState()
    @AppStorage(AppLayout.storageKey) private var layout: AppLayout = .tabs
    /// The look in use sets the colour of the app's controls.
    @AppStorage(TodayStyle.storageKey) private var todayStyle = TodayStyle()
    @Environment(\.colorScheme) private var scheme
    @AppStorage(SearchTabKeyboard.storageKey) private var searchOpensKeyboard = true
    @State private var layoutChangePending = false
    @Environment(AgendaModel.self) private var agenda
    @Environment(UpdateFeed.self) private var feed
    /// Moved on when a lesson starts or ends, so the accessory follows the
    /// timetable without redrawing the whole tab tree every minute.
    @State private var now = Date.now

    /// The class now, except on Oggi when the page already shows it.
    private var current: CurrentClass? {
        guard todayStyle.wantsCurrentClassAccessory || shell.selection != .today else { return nil }
        return CurrentClass.forAccessory(from: agenda.events, now: now)
    }

    var body: some View {
        // One tree for both layouts. Swapping two whole screens cross-faded
        // two navigation bars, two pages and a tab bar at once; here the page
        // and its bar stay put and only the bottom changes — the tab bar
        // slides away as the panel rises, and back.
        tabs
            // Personalizza, over the app that stays underneath: the look in use
            // shrinks out of it into the gallery, and grows back on close.
            .overlay {
                if shell.isCustomizing { CustomizeOggi() }
            }
            .onAppear {
                shell.singlePage = layout == .singlePage
                #if DEBUG
                // `-OpenPlace calendar` opens a place at launch, for trying it out.
                if let raw = UserDefaults.standard.string(forKey: "OpenPlace"),
                   let place = NewDestination(rawValue: raw) {
                    shell.route(to: .destination(place))
                }
                #endif
            }
            .onChange(of: layout) { _, new in
                if shell.showingSettings {
                    layoutChangePending = true
                    shell.showingSettings = false
                } else {
                    show(new)
                }
            }
            .sheet(isPresented: $shell.showingSettings, onDismiss: {
                shell.settingsPath = []
                guard layoutChangePending else { return }
                layoutChangePending = false
                show(layout)
            }) { SettingsSheet() }
            .sheet(item: $shell.detail) { detail in
                switch detail {
                case .event(let event): EventDetailView(event: event)
                case .exam(let exam): ExamDetailView(exam: exam)
                }
            }
            .appShellDuties { shell.route(to: NewRoute($0)) }
            // Outermost, so the sheets see the same shell as the page. Placed
            // before them, the sheets fell back to the default instance: the
            // settings sheet wrote to a stray copy and its dismissal never
            // found the pending change.
            .environment(\.shell, shell)
    }

    /// The layout on screen trails the stored setting, so a change made in
    /// Impostazioni first closes the sheet, then animates.
    private func show(_ layout: AppLayout) {
        if layout == .singlePage { shell.selection = .today }
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) {
            shell.singlePage = layout == .singlePage
        }
    }

    private var tabs: some View {
        TabView(selection: $shell.selection) {
            Tab("Oggi", systemImage: "calendar.day.timeline.left", value: .today) {
                TodayTab().accessibilityIdentifier("tab-today")
            }
            Tab(NewDestination.courses.title, systemImage: NewDestination.courses.systemImage, value: .courses) {
                CoursesTab().accessibilityIdentifier("tab-courses")
            }
            Tab(NewDestination.career.title, systemImage: NewDestination.career.systemImage, value: .career) {
                CareerTab().accessibilityIdentifier("tab-career")
            }
            // What changed since the feed was last opened, one per fact.
            .badge(feed.unreadCount)
            Tab(value: .search, role: .search) {
                SearchTab().accessibilityIdentifier("tab-search")
            }
        }
        // Above the tab bar while there is a class today, like Music's player.
        .currentClassAccessory(shell.singlePage ? nil : current)
        // Around the day shown, so a day picked two months out is not empty.
        .task(id: shell.day) { await agenda.ensureLoaded(covering: shell.day) }
        // Wakes at the next start or end of a lesson today rather than every
        // minute: between lessons nothing on the accessory can change.
        .task(id: agenda.events.count) {
            while !Task.isCancelled {
                let wait = CurrentClass.nextChange(in: agenda.events, after: .now).timeIntervalSinceNow
                try? await Task.sleep(for: .seconds(max(wait, 1)))
                now = .now
            }
        }
        // Hangs and hitches in the field arrive split by tab.
        .onChange(of: shell.selection, initial: true) { _, tab in
            PerformanceStates.tabSelected(shell.singlePage ? "single" : tab.rawValue)
        }
        .onChange(of: shell.singlePage) { _, single in
            PerformanceStates.tabSelected(single ? "single" : shell.selection.rawValue)
        }
        .onDisappear { PerformanceStates.tabSelected(nil) }
        .tint(todayStyle.controlTint(scheme))
        .preferredColorScheme(todayStyle.appearance.colorScheme)
        // Selecting the search tab opens its field straight away, unless the
        // student turned that off in Impostazioni.
        .tabViewSearchActivation(searchOpensKeyboard ? .searchTabSelection : .automatic)
        .toolbarMinimizationBehavior(.onScrollDown, for: .tabBar)
    }
}

#Preview("Nuova struttura") {
    NewRootView().previewEnvironment()
}

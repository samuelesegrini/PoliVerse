import SwiftUI

/// Routes between the first run, sign-in and the app shell, and is the shell: the tab
/// layout, or a single page with a bottom panel.
///
/// Both layouts reach the same places, listed once in ``NewDestination``, and share one
/// view tree — only the bottom changes when the layout does, so switching does not
/// cross-fade two navigation bars and two pages at once.
///
/// Oggi shows the day's lessons, exams and deadlines; the full calendar lives under
/// search. Corsi holds the enrolled teachings and their materials. See
/// `docs/information-architecture.md`.
struct RootView: View {
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// The shared ``WhatsNewState``, from the environment.
    @Environment(WhatsNewState.self) private var whatsNew

    /// Which tab or panel row is showing, and the panel's own state.
    /// Which layout the student chose: the tab bar, or the single page.
    @State private var shell = ShellState()
    @AppStorage(AppLayout.storageKey) private var layout: AppLayout = .tabs
    /// The look in use sets the colour of the app's controls.
    @AppStorage(TodayStyle.storageKey) private var todayStyle = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    @AppStorage(SearchTabKeyboard.storageKey) private var searchOpensKeyboard = true
    @State private var layoutChangePending = false
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// The shared ``UpdateFeed``, from the environment.
    @Environment(UpdateFeed.self) private var feed
    /// Moved on when a lesson starts or ends, so the accessory follows the
    /// timetable without redrawing the whole tab tree every minute.
    @State private var now = Date.now
    /// Whether the window is wide enough for a sidebar.
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Whether the shell draws a sidebar: regular width, and not the single
    /// page, which is one page with a panel and has no bar to widen.
    private var hasSidebar: Bool { sizeClass == .regular && !shell.singlePage }

    /// What the tab view has selected: one of the four tabs, or, at regular
    /// width, one of the places in the sidebar.
    ///
    /// Held here and mirrored to ``ShellState`` rather than computed from it.
    /// A `TabView` handed a computed `Binding` over the shell drew nothing at
    /// all — no tabs and no page — so the selection is stored, and the two
    /// `onChange`s on the tab view keep it and the shell agreeing in both
    /// directions: a tap here reaches the shell, and a route from Siri, a
    /// control or a notification reaches the tab view.
    @State private var tabSelection = ShellSelection.tab(.today)

    /// The selection the shell's own state implies.
    private var shellSelection: ShellSelection {
        shell.sidebarPlace.map(ShellSelection.place) ?? .tab(shell.selection)
    }

    /// The class now, except on Oggi when the page already shows it.
    private var current: CurrentClass? {
        guard todayStyle.wantsCurrentClassAccessory || shell.selection != .today else { return nil }
        return CurrentClass.forAccessory(from: agenda.events, now: now)
    }

    /// The view's content.
    var body: some View {
        Group {

            switch session.state {
            case .loading:
                LaunchGate()
            // The first run explains the app before asking for an account,
            // so it owns the sign-in rather than sitting in front of it.
            // Once it has been through, a signed-out session is someone who
            // already knows what this is — switching career, or coming back
            // — and gets the plain login screen instead.
            case .signedOut, .failed:
                if onboarding.isComplete { LoginView() } else { JourneyView() }
            // The web sheet is already gone by the time the session reaches
            // here — CieID/SPID handed control back to this app, not to a
            // screen. Showing the plain login screen underneath made that
            // stretch (code exchange, then `/jaf/internal/user`) look like
            // the login had silently failed and gone back to the start.
            //
            // During the first run the journey stays up instead: its sign-in
            // step says "Accesso in corso…" over the same landscape, and the
            // career and WeBeep sheets follow it there.
            case .exchangingCode:
                if onboarding.isComplete { SigningInView() } else { JourneyView() }
            // The journey's last card sits over the app, which is drawn under
            // it from the last step so pulling the card down reveals the real
            // thing. One ZStack either way, so the shell keeps its identity
            // when the card goes and the journey is complete.
            case .signedIn:
                ZStack {
                    if onboarding.isComplete || onboarding.revealsApp {
                        shellContent
                    }
                    if !onboarding.isComplete {
                        JourneyView()
                    }
                }
            }
        }
        // The look's colour and lighting, around everything rather than inside
        // the tabs. A sheet inherits the environment of the view its modifier
        // is attached to, so a tint set under the sheets left Impostazioni and
        // the detail sheets on the system's blue while the app behind them was
        // not; and set inside the tabs it never reached the login screen.
        .lookControls()
        // Sample data is its own population in the field numbers.
        .onChange(of: session.useMockData, initial: true) { _, sample in
            PerformanceStates.dataSource(usesSampleData: sample)
        }
        .task {
            // Launch, as a student feels it, ends when the account is back —
            // not at the first frame, which is a spinner.
            await PerformanceMonitor.trackLaunch("session-restore") {
                let interval = PerfSignpost.begin(.sessionRestore)
                defer { PerfSignpost.end(interval) }
                await session.login.restore()
            }
            // After the restore, not before: a token in the Keychain is what
            // says this install predates the onboarding.
            if session.student != nil { onboarding.adoptExistingInstall() }
        }
    }

    // MARK: - Tab shell

    /// The shell in either layout: one tree, with the page and its bar kept in place and only
    /// the bottom — tab bar or panel — changing.
    private var shellContent: some View {
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
                case .deadline(let deadline): DeadlineDetailView(deadline: deadline)
                }
            }
            // What changed in this update, once. Only past the first run:
            // during onboarding there is nothing for it to be new against.
            .sheet(isPresented: Binding(get: { !whatsNew.showing.isEmpty },
                                        set: { if !$0 { whatsNew.dismiss() } })) {
                WhatsNewView(notes: whatsNew.showing) { whatsNew.dismiss() }
            }
            .task { whatsNew.presentIfNeeded() }
            .appShellDuties { shell.route(to: NewRoute($0)) }
            // Outermost, so the sheets see the same shell as the page. Placed
            // before them, the sheets fell back to the default instance: the
            // settings sheet wrote to a stray copy and its dismissal never
            // found the pending change.
            .environment(\.shell, shell)
    }

    /// Moves to a layout, selecting Oggi first when moving to the single page so the panel
    /// opens onto something.
    ///
    /// - Parameter layout: The layout to show.
    private func show(_ layout: AppLayout) {
        if layout == .singlePage { shell.selection = .today }
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) {
            shell.singlePage = layout == .singlePage
        }
    }

    /// The four tabs: Oggi, Corsi, Carriera and Cerca — and, at regular width,
    /// the places from Cerca as sidebar items of their own.
    ///
    /// On an iPad the tab bar was the whole navigation: six of the app's eight
    /// places were reachable only by opening Cerca and tapping a row, on a
    /// screen with room to list them all. At regular width the same places
    /// become a section of the sidebar; at compact width nothing changes, so
    /// the iPhone keeps its four tabs rather than growing a "More" tab.
    private var tabs: some View {
        TabView(selection: $tabSelection) {
            Tab("Oggi", systemImage: "calendar.day.timeline.left", value: ShellSelection.tab(.today)) {
                TodayTab().accessibilityIdentifier("tab-today")
            }
            Tab(NewDestination.courses.title, systemImage: NewDestination.courses.systemImage,
                value: ShellSelection.tab(.courses)) {
                CoursesTab().accessibilityIdentifier("tab-courses")
            }
            Tab(NewDestination.career.title, systemImage: NewDestination.career.systemImage,
                value: ShellSelection.tab(.career)) {
                CareerTab().accessibilityIdentifier("tab-career")
            }
            // What changed since the feed was last opened, one per fact.
            .badge(feed.unreadCount)
            if hasSidebar {
                TabSection("Altro") {
                    ForEach(NewDestination.inSearch) { place in
                        Tab(place.title, systemImage: place.systemImage, value: ShellSelection.place(place)) {
                            SidebarPlace(place: place)
                        }
                    }
                }
            }
            Tab(value: ShellSelection.tab(.search), role: .search) {
                SearchTab().accessibilityIdentifier("tab-search")
            }

        }
        // Applied only at regular width: `.sidebarAdaptable` on an iPhone
        // still draws a tab bar, but pushes anything past the fifth tab into a
        // "More" tab, and the compact layout should keep its four.
        .modifier(SidebarStyle(enabled: hasSidebar))
        // A tap on a tab or a sidebar row, into the shell.
        .onChange(of: tabSelection) { _, selection in
            switch selection {
            case .tab(let tab):
                shell.sidebarPlace = nil
                shell.selection = tab
            case .place(let place):
                shell.sidebarPlace = place
            }
        }
        // A route from outside — Siri, a control, a notification — back out to
        // the tab view. Only when the two disagree, so neither `onChange` sets
        // off the other.
        .onChange(of: shellSelection) { _, selection in
            guard tabSelection != selection else { return }
            tabSelection = selection
        }
        .onChange(of: hasSidebar, initial: true) { _, sidebar in
            shell.hasSidebar = sidebar
            // Coming back to a tab bar, a sidebar place has nowhere to be: it
            // goes back to being a row inside Cerca.
            guard !sidebar, let place = shell.sidebarPlace else { return }
            shell.route(to: .destination(place))
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
        // A sidebar place is its own screen in the field numbers, not a fifth
        // reading of whichever tab happened to be selected behind it.
        .onChange(of: shell.sidebarPlace) { _, place in
            guard !shell.singlePage else { return }
            PerformanceStates.tabSelected(place?.rawValue ?? shell.selection.rawValue)
        }
        .onChange(of: shell.singlePage) { _, single in
            PerformanceStates.tabSelected(single ? "single" : shell.selection.rawValue)
        }
        .onDisappear { PerformanceStates.tabSelected(nil) }
        // Selecting the search tab opens its field straight away, unless the
        // student turned that off in Impostazioni.
        .tabViewSearchActivation(searchOpensKeyboard ? .searchTabSelection : .automatic)
        .modifier(MinimizeBehaviour(enabled: !hasSidebar, behaviour: todayStyle.appTabBar))
    }
}

// MARK: - Previews

#Preview("Struttura") {
    RootView().previewEnvironment()
}

/// The gap between the launch screen and the first real screen.
///
/// Holds the launch screen's own background rather than drawing over it, so there is
/// nothing to see across the handover.
///
/// The wait is normally a Keychain read — a frame or two — and a spinner that appears and
/// vanishes inside a tenth of a second is a flash rather than information, so one fades
/// in only if the wait runs long.
private struct LaunchGate: View {
    /// Set once the wait has run long enough to be worth a spinner.
    @State private var isTakingAWhile = false

    /// The view's content.
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .overlay {
                ProgressView()
                    .controlSize(.large)
                    .opacity(isTakingAWhile ? 1 : 0)
            }
            .task {
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.easeOut(duration: 0.2)) { isTakingAWhile = true }
            }
            .accessibilityLabel("Apertura di PoliVerse")
    }
}



/// What the shell's tab view has selected.
///
/// At compact width this is always a tab; at regular width the sidebar adds
/// the places that are otherwise rows inside Cerca, and one of those can be
/// selected instead. Kept separate from ``NewDestination/Tab``, which names
/// the four tabs and is what the field metrics are split by.
nonisolated enum ShellSelection: Hashable, Sendable {
    /// One of the four tabs.
    case tab(NewDestination.Tab)
    /// One of the places listed in the sidebar.
    case place(NewDestination)
}

/// The tab bar's minimise behaviour, which only a tab bar has.
private struct MinimizeBehaviour: ViewModifier {
    /// Whether there is a tab bar to minimise.
    let enabled: Bool
    /// What the look in use asks of the bar.
    let behaviour: TabBarBehaviour

    /// The view, with the behaviour or without it.
    ///
    /// - Parameter content: The tab view.
    /// - Returns: The tab view.
    func body(content: Content) -> some View {
        if enabled { content.tabBarMinimizeBehavior(behaviour.system) } else { content }
    }
}

/// The sidebar style, applied only where there is room for a sidebar.
///
/// A conditional `tabViewStyle` cannot be written inline: the two styles are
/// different types, and the ternary has nowhere to land.
private struct SidebarStyle: ViewModifier {
    /// Whether the sidebar style applies.
    let enabled: Bool

    /// The view, with the style or without it.
    ///
    /// - Parameter content: The tab view.
    /// - Returns: The styled tab view.
    func body(content: Content) -> some View {
        if enabled { content.tabViewStyle(.sidebarAdaptable) } else { content }
    }
}

/// A place as a sidebar item: its own navigation stack, since it is a root
/// here rather than a screen pushed inside Cerca's.
private struct SidebarPlace: View {
    /// The place to show.
    let place: NewDestination

    /// The view's content.
    var body: some View {
        NavigationStack {
            place.screen
                .profileButton()
                .dataStatusLine()
        }
        .accessibilityIdentifier("sidebar-\(place.rawValue)")
    }
}

import SwiftUI

/// Routes between login and the tab bar, and is the tab bar: the restructured
/// app shell, in the layout the student chose, four tabs instead of five, or
/// a single page with a bottom panel.
///
/// Used to be two types — this router and a separate `NewRootView` for the
/// shell — split apart when the shell was a rewrite sitting next to the
/// interface it was replacing. That older interface is gone, so the "New"
/// was already misleading, and the split stopped earning its keep: routing
/// and shell had nothing left to keep apart from each other.
///
/// Oggi merges the old Home and Calendario's day, since both show the same
/// lessons and exams filtered differently; the full calendar lives in Cerca.
/// Corsi replaces the WeBeep tab and the Home course grid. Both layouts reach
/// the same places, listed once in ``NewDestination``. See
/// `docs/information-architecture.md`.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(OnboardingState.self) private var onboarding
    @Environment(WhatsNewState.self) private var whatsNew

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
                if onboarding.isComplete { LoginView() } else { OnboardingView() }
            // The web sheet is already gone by the time the session reaches
            // here — CieID/SPID handed control back to this app, not to a
            // screen. Showing the plain login screen underneath made that
            // stretch (code exchange, then `/jaf/internal/user`) look like
            // the login had silently failed and gone back to the start.
            case .exchangingCode:
                SigningInView()
            case .signedIn:
                if !onboarding.isComplete {
                    OnboardingView()
                } else {
                    shellContent
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
        // Selecting the search tab opens its field straight away, unless the
        // student turned that off in Impostazioni.
        .tabViewSearchActivation(searchOpensKeyboard ? .searchTabSelection : .automatic)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

// MARK: - Previews

#Preview("Struttura") {
    RootView().previewEnvironment()
}

/// The gap between the launch screen and the first real screen.
///
/// Holds the launch screen's own background rather than drawing over it, so
/// there is nothing to see across the handover — no white page with a spinner
/// parachuted into the middle of it, which is what this was.
///
/// The spinner is kept, but only for the wait that deserves one. What happens
/// here is a Keychain read; ``LoginFlow/restore()`` no longer puts the service
/// directory's two network round-trips in front of it. So the usual case is a
/// frame or two, and a spinner that appears and vanishes inside a tenth of a
/// second is a flash rather than information. If the wait does run long — a
/// device under load, a slow unlock — it fades in and says so.
private struct LaunchGate: View {
    @State private var isTakingAWhile = false

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


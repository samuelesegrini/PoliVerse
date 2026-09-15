import SwiftUI

/// Routes between login and the tab bar, and adapts to iPad width.
struct RootView: View {
    @Environment(Session.self) private var session
    @Environment(OnboardingState.self) private var onboarding
    /// The restructured interface being tried out, on by default on this
    /// branch; Impostazioni switches back to the current one.
    @AppStorage(NewInterface.storageKey) private var usesNewInterface = true

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
                if !onboarding.isComplete {
                    OnboardingView()
                } else if usesNewInterface {
                    NewRootView()
                } else {
                    MainTabView()
                }
            }
        }
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
                await session.restore()
            }
            // After the restore, not before: a token in the Keychain is what
            // says this install predates the onboarding.
            if session.student != nil { onboarding.adoptExistingInstall() }
        }
    }
}

struct MainTabView: View {
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

    @Environment(UpdateFeed.self) private var feed

    @State private var selection = "home"

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "graduationcap", value: "home") { HomeView() }
            Tab("WeBeep", systemImage: "books.vertical", value: "webeep") { WeBeepView() }
            Tab("Calendario", systemImage: "calendar", value: "calendar") { CalendarView() }
            Tab("Carriera", systemImage: "chart.bar", value: "career") { CareerView() }
                // What changed since the feed was last opened, one per fact.
                .badge(feed.unreadCount)
            Tab("Cerca", systemImage: "magnifyingglass", value: "search", role: .search) {
                SearchView()
            }
        }
        // Hangs and hitches in the field arrive split by tab.
        .onChange(of: selection, initial: true) { _, tab in
            PerformanceStates.tabSelected(tab)
        }
        .onDisappear { PerformanceStates.tabSelected(nil) }
        // Above the tabs rather than on one screen: sample data replaces
        // every one of them, so saying it once on the Home would leave the
        // libretto looking like a real libretto.
        .safeAreaInset(edge: .top, spacing: 0) { DemoModeBanner() }
        .appShellDuties(route: route(to:))
    }
}

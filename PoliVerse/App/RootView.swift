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
    var body: some View {
        TabView {
            Tab("Home", systemImage: "graduationcap") { HomeView() }
            Tab("WeBeep", systemImage: "books.vertical") { WeBeepView() }
            Tab("Calendario", systemImage: "calendar") { CalendarView() }
            Tab("Carriera", systemImage: "chart.bar") { CareerView() }
            Tab("Cerca", systemImage: "magnifyingglass", role: .search) { SearchView() }
        }
    }
}

import SwiftUI

/// The Watch app's pages, one vertical stack the Digital Crown scrolls through.
///
/// The first page answers the question a raised wrist is asking — where do I
/// have to be, and when — and every other page is one turn of the crown away.
/// Pages with nothing to say are left out rather than shown empty.
struct WatchRootView: View {
    /// The link to the phone.
    @Environment(WatchBridge.self) private var bridge
    /// Whether the app is in front.
    @Environment(\.scenePhase) private var scenePhase

    /// The pages, in crown order.
    enum Page: Hashable {
        /// The lecture on now or the next one.
        case now
        /// The next few days.
        case agenda
        /// The sittings ahead.
        case exams
        /// Average and credits.
        case career
    }

    /// The page on screen.
    @State private var page = Page.now
    /// The entries pushed on the stack, by identity.
    @State private var path: [Int] = []

    /// The view's content.
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let snapshot = bridge.snapshot {
                    pages(snapshot)
                } else {
                    WatchWaitingView()
                }
            }
            .navigationDestination(for: Int.self) { id in
                if let entry = bridge.snapshot?.entries.first(where: { $0.id == id }) {
                    WatchEntryDetail(entry: entry)
                } else {
                    ContentUnavailableView("Non più in programma", systemImage: "calendar.badge.minus")
                }
            }
        }
        // Opening the app is the request for fresh data: no button, no pull.
        // Asked again when the phone comes into reach with the app still in
        // front, which covers the session not being up yet at launch.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { bridge.refreshIfStale() }
        }
        .onChange(of: bridge.isReachable) { _, reachable in
            if reachable, scenePhase == .active { bridge.refreshIfStale() }
        }
        // A complication or a Smart Stack card opens the app on the entry it
        // was showing, on top of the first page, so Back lands somewhere
        // useful.
        .onOpenURL { url in
            guard let id = WatchSnapshot.Entry.id(from: url) else { return }
            page = .now
            path = [id]
        }
    }

    /// The pages for a snapshot.
    ///
    /// - Parameter snapshot: What the phone last sent.
    /// - Returns: The paged stack.
    private func pages(_ snapshot: WatchSnapshot) -> some View {
        TabView(selection: $page) {
            WatchNowPage(snapshot: snapshot) {
                withAnimation { page = .agenda }
            }
            .tag(Page.now)

            WatchAgendaPage(snapshot: snapshot)
                .tag(Page.agenda)

            if !snapshot.exams.isEmpty {
                WatchExamsPage(exams: snapshot.exams)
                    .tag(Page.exams)
            }

            if snapshot.mean != nil || snapshot.earnedCFU > 0 {
                WatchCareerPage(snapshot: snapshot)
                    .tag(Page.career)
            }
        }
        .tabViewStyle(.verticalPage)
    }
}

/// What is shown before the phone has sent anything.
///
/// Names the cause, because "apri PoliVerse sull'iPhone" is something the
/// reader can act on and a spinner is not.
struct WatchWaitingView: View {
    /// The link to the phone.
    @Environment(WatchBridge.self) private var bridge

    /// The view's content.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Nessun dato ancora")
                    .font(.headline)
                if bridge.isRefreshing {
                    Label("Chiedo all'iPhone…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tieni l'iPhone vicino, o apri PoliVerse lì: l'orario arriva da lì.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("PoliVerse")
    }
}

#Preview("In attesa") {
    WatchRootView()
        .environment(WatchBridge.shared)
}

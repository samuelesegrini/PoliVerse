import SwiftUI

/// The bottom of the single-page layout, presented as a real sheet like the
/// one in Maps: it rests small, grows as the student scrolls in it, scrolls
/// its list only once it is full height, and lets the page behind stay live.
struct SinglePagePanel: View {
    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    @State private var now = Date.now

    /// The look in use, which says whether Oggi already shows the current class.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    /// The class now, unless Oggi already shows it as a section.
    private var current: CurrentClass? {
        guard style.wantsCurrentClassAccessory else { return nil }
        return CurrentClass.forAccessory(from: agenda.events, now: now)
    }

    /// The height the panel rests at: enough for the search row and nothing more.
    private static let peek = PresentationDetent.height(92)

    /// The view's content.
    var body: some View {
        PanelContent(current: current, isFull: shell.panelDetent == .full) {
            withAnimation(.snappy) { shell.panelDetent = .full }
        }
        .presentationDetents([Self.peek, .medium, .large], selection: detent)
        // Scrolling first resizes the sheet; only at full height does the
        // list itself scroll.
        .presentationContentInteraction(.resizes)
        .presentationBackgroundInteraction(.enabled)
        .interactiveDismissDisabled()
        .onAppear { shell.panelIsOnScreen = true }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = .now
            }
        }
    }

    /// The sheet's detent, read and written as the shell's own ``ShellState/PanelDetent``.
    private var detent: Binding<PresentationDetent> {
        Binding {
            switch shell.panelDetent {
            case .peek: Self.peek
            case .half: .medium
            case .full: .large
            }
        } set: { new in
            shell.panelDetent = new == .large ? .full : new == .medium ? .half : .peek
        }
    }
}

/// Everything that is not the day: search first, then the places a student
/// goes to — the same places the tab layout reaches.
struct PanelContent: View {
    /// The class now, shown above the list when there is one.
    var current: CurrentClass?
    /// True once the panel is at full height, where its list scrolls.
    var isFull = false
    /// Takes the panel to full height, for a row that needs the whole screen.
    var expand: () -> Void = {}
    /// The environment's `shell`.
    @Environment(\.shell) private var shell

    /// The view's content.
    var body: some View {
        NavigationStack(path: Binding(get: { shell.panelPath }, set: { shell.panelPath = $0 })) {
            List {
                Section {
                    // A row that opens Cerca, drawn as its field: typing here
                    // would search nothing.
                    NavigationLink(value: NewRoute.search) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("Cerca corsi, aule, docenti")
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(.quaternary.opacity(0.6), in: .capsule)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("panel-search")

                    if let current {
                        CurrentClassButton(current: current)
                            .frame(height: 54)
                            .listRowBackground(Rectangle().fill(.primary.opacity(0.06)))
                    }
                }
                Section {
                    ForEach(NewDestination.panel) { place in
                        destination(place)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 6, for: .scrollContent)
            // Fixed until full height, so a drag in the list moves the sheet.
            .scrollDisabled(!isFull)
            .toolbar(.hidden, for: .navigationBar)
            .containerBackground(.clear, for: .navigation)
            .navigationDestination(for: NewRoute.self) { route in
                switch route {
                case .today: EmptyView()
                // The places are the panel's own rows already.
                case .search: SearchView(embedded: true, places: [])
                case .destination(let place): place.screen
                }
            }
        }
        // A pushed screen needs the whole height to be used.
        .onChange(of: shell.panelPath) { _, path in
            if !path.isEmpty { expand() }
        }
    }

    /// One place as a row of the panel's list.
    ///
    /// - Parameter place: The place to offer.
    /// - Returns: The row.
    private func destination(_ place: NewDestination) -> some View {
        NavigationLink(value: NewRoute.destination(place)) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.title)
                    Text(place.detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: place.systemImage)
            }
        }
        // Soft rows on the glass instead of the list's solid cells.
        .listRowBackground(Rectangle().fill(.primary.opacity(0.06)))
        .accessibilityIdentifier("panel-\(place.id)")
    }
}

#Preview("Pannello") {
    PanelContent().previewEnvironment()
}

import SwiftUI

/// The bottom of the single-page layout, presented as a real sheet like the
/// one in Maps: it rests small, grows as the student scrolls in it, scrolls
/// its list only once it is full height, and lets the page behind stay live.
struct SinglePagePanel: View {
    @Environment(\.shell) private var shell
    @Environment(AgendaService.self) private var agenda
    @State private var now = Date.now

    private var current: CurrentClass? { CurrentClass.forAccessory(from: agenda.events, now: now) }

    private static let peek = PresentationDetent.height(92)

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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = .now
            }
        }
    }

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
/// goes to.
struct PanelContent: View {
    var current: CurrentClass?
    var isFull = false
    var expand: () -> Void = {}
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Cerca corsi, aule, docenti", text: $query)
                            .onTapGesture(perform: expand)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(.quaternary.opacity(0.6), in: .capsule)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if let current {
                        CurrentClassAccessory(current: current)
                            .frame(height: 54)
                            .listRowBackground(Rectangle().fill(.primary.opacity(0.06)))
                    }
                }
                Section {
                    destination("Corsi", "books.vertical", "Materiali, avvisi e appelli")
                    destination("Carriera", "graduationcap", "Libretto, piano e media")
                    destination("Calendario", "calendar", "Settimana e mese")
                }
                Section {
                    destination("Aule libere", "door.left.hand.open", "Adesso e più tardi")
                    destination("Mappa", "map", "Campus e edifici")
                    destination("Dal Politecnico", "newspaper", "Notizie e avvisi")
                }
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 6, for: .scrollContent)
            // Fixed until full height, so a drag in the list moves the sheet.
            .scrollDisabled(!isFull)
            .toolbar(.hidden, for: .navigationBar)
            .containerBackground(.clear, for: .navigation)
        }
    }

    private func destination(_ title: LocalizedStringKey, _ icon: String, _ detail: LocalizedStringKey) -> some View {
        NavigationLink {
            ContentUnavailableView(title, systemImage: icon, description: Text(detail))
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon)
            }
        }
        // Soft rows on the glass instead of the list's solid cells.
        .listRowBackground(Rectangle().fill(.primary.opacity(0.06)))
    }
}

#Preview("Pannello") {
    PanelContent().previewEnvironment()
}

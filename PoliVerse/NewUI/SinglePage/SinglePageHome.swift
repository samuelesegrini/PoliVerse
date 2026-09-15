import SwiftUI

/// The bottom of the single-page layout: every other part of the app in a
/// ``BottomPanel``, with the current class riding on top of it.
struct SinglePagePanel: View {
    @State private var detent: BottomPanel<PanelContent, AnyView>.Detent = .peek
    @Environment(AgendaService.self) private var agenda
    @State private var now = Date.now

    private var current: CurrentClass? { CurrentClass.forAccessory(from: agenda.events, now: now) }

    var body: some View {
        BottomPanel(detent: $detent) {
            PanelContent(expand: { withAnimation(.snappy) { detent = .full } })
        } accessory: {
            // The same bar Music-style tab bars carry, above the panel.
            AnyView(Group {
                if let current {
                    CurrentClassAccessory(current: current)
                        .frame(height: 54)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .padding(.horizontal, 16)
                }
            })
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = .now
            }
        }
    }
}

/// Everything that is not the day: search first, then the places a student
/// goes to.
struct PanelContent: View {
    var expand: () -> Void = {}
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
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
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Cerca corsi, aule, docenti", text: $query)
                        .onTapGesture(perform: expand)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.quaternary.opacity(0.6), in: .capsule)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .background(.clear)
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
    }
}

#Preview("Pannello") {
    SinglePagePanel().previewEnvironment()
}

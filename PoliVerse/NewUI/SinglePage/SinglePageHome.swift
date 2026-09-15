import SwiftUI

/// The single-page layout: a landing page for the day under ``TodayBar``, and
/// every other part of the app in a ``BottomPanel``.
struct SinglePageHome: View {
    @State private var day = Date.now
    @State private var detent: BottomPanel<PanelContent, AnyView>.Detent = .peek
    @Environment(AgendaService.self) private var agenda
    @State private var now = Date.now

    private var current: CurrentClass? { CurrentClass.forAccessory(from: agenda.events, now: now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LandingPage(day: day)
                    .padding(.bottom, 140)
            }
            .todayBar(day: $day)
        }
        .overlay {
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
            .animation(.snappy, value: detent)
        }
        .task { await agenda.load(around: .now) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = .now
            }
        }
    }
}

/// The day at a glance. Placeholder sections for now, in the order the
/// redesign puts them.
private struct LandingPage: View {
    let day: Date
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Buona giornata!")
                    .font(.headline)
                Text(day.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(locale)).replacingOccurrences(of: "/", with: "."))
                    .font(.system(size: 72, weight: .black))
                    .fontWidth(.expanded)
                Text(day.formatted(.dateTime.weekday(.abbreviated).locale(locale)).uppercased())
                    .font(.system(size: 72, weight: .black))
                    .fontWidth(.expanded)
                    .padding(.top, -24)
            }

            placeholder("In arrivo", "checklist", height: 110)
            placeholder("Orario", "calendar.day.timeline.left", height: 220)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func placeholder(_ title: LocalizedStringKey, _ icon: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            RoundedRectangle(cornerRadius: 28)
                .fill(.quaternary.opacity(0.5))
                .frame(height: height)
                .overlay { Image(systemName: icon).font(.largeTitle).foregroundStyle(.tertiary) }
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

#Preview("Pagina unica") {
    SinglePageHome().previewEnvironment()
}

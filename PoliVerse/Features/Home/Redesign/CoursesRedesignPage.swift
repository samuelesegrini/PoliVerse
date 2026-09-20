import SwiftUI

/// Le cinque opzioni sui dati veri, con un selettore in cima.
///
/// Serve a scegliere, non a spedire: quando una vince, resta la sua vista e
/// questa pagina sparisce insieme alle altre quattro.
///
/// La casa la mette la pagina, non le opzioni: il titolo nella grafia di Oggi
/// con la banda della settimana sotto, la larghezza e i margini di ogni pagina
/// dell'app, il titolo che sale nella barra, la ricerca del sistema. Così il
/// confronto è fra cinque elenchi dentro la stessa app, non fra cinque app.
struct CoursesRedesignPage: View {
    enum Option: String, CaseIterable, Identifiable {
        case agenda, grid, focus, index, dashboard
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .agenda: "Agenda"
            case .grid: "Griglia"
            case .focus: "Focus"
            case .index: "Indice"
            case .dashboard: "Cruscotto"
            }
        }

        var letter: String {
            switch self {
            case .agenda: "A"
            case .grid: "B"
            case .focus: "C"
            case .index: "D"
            case .dashboard: "E"
            }
        }
    }

    @Environment(CourseModel.self) private var courses
    @Environment(AgendaModel.self) private var agenda
    @Environment(CareerModel.self) private var career
    @Environment(UpdateFeed.self) private var feed

    @AppStorage("courses-redesign-option") private var option = Option.agenda
    /// Acceso, la pagina usa i dati finti del kit: una lezione in corso, una
    /// più tardi, una domani. È l'unico modo di giudicare le opzioni quando
    /// oggi è domenica e l'agenda è vuota.
    @State private var useSamples = true
    @State private var query = ""

    private var shown: [Course] {
        useSamples ? Course.samples : courses.visibleCourses
    }

    private var briefs: [CourseBrief] {
        useSamples
            ? CourseBrief.samples
            : CourseBrief.make(courses: courses.visibleCourses, agenda: agenda, career: career, feed: feed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LookHeader("Corsi", subtitle: Text("\(briefs.count) corsi · prova \(option.letter)")) {
                    WeekLoadFigure(events: agenda.events, courses: shown)
                }
                picker
                Group {
                    switch option {
                    case .agenda: CoursesOptionAgenda(courses: briefs)
                    case .grid: CoursesOptionGrid(courses: briefs)
                    case .focus: CoursesOptionFocus(courses: briefs)
                    case .index: CoursesOptionIndex(courses: briefs, query: query)
                    case .dashboard: CoursesOptionDashboard(courses: briefs)
                    }
                }
                .transition(.opacity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .animation(.snappy(duration: 0.25), value: option)
        .collapsingTitle("Corsi · prove")
        // Solo l'indice usa la ricerca; sulle altre la barra sarebbe un
        // comando che non fa niente.
        .searchable(text: $query, isPresented: .constant(option == .index), prompt: "Cerca un corso o un docente")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle("Dati di esempio", systemImage: "wand.and.stars", isOn: $useSamples)
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
            }
        }
        .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
    }

    private var picker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Option.allCases) { item in
                    LookChip(title: Text(verbatim: item.letter) + Text(" · ") + Text(item.title),
                             isOn: item == option) {
                        option = item
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }
}

/// L'involucro in cui guardare una singola opzione: la pagina dell'app, con
/// il suo titolo, la sua banda e i suoi margini, e dentro solo l'elenco.
struct CoursesOptionPreview<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LookHeader("Corsi", subtitle: Text("6 corsi · 2024/25")) {
                        WeekLoadFigure(events: AgendaEvent.samples(around: .now), courses: Course.samples)
                    }
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .collapsingTitle("Corsi")
        }
        .previewEnvironment()
    }
}

#Preview("Corsi · cinque prove") {
    NavigationStack { CoursesRedesignPage() }.previewEnvironment()
}

#if DEBUG
/// La rotta che porta alle prove, solo in debug.
struct CoursesRedesignRoute: Hashable {}
#endif

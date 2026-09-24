import SwiftUI

/// Carriera: what expires, where you are, and then the lists.
///
/// The order answers three questions, in the order they are asked:
///
/// 1. **What expires** — ``CareerNowCard``, absent when nothing does.
/// 2. **Where am I** — ``CareerStandingCard``: one figure with its direction,
///    the marks behind it, the credits and what is left.
/// 3. **The detail** — the libretto by year, or the sittings by deadline.
///
/// There is no summary tab: 1 and 2 sit permanently above the picker and *are*
/// the summary, without repeating the lists under it. Novità, the study plan
/// and the simulator are destinations, so they live in the toolbar rather than
/// taking the top of the page from the content.
struct CareerView: View {
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``UpdateFeed``, from the environment.
    @Environment(UpdateFeed.self) private var feed

    /// Which of the two lists is shown under the cards.
    @State private var scope: Scope = .libretto
    /// The sitting whose detail sheet is open, if any.
    @State private var selectedExam: ExamSession?
    /// Whether the study plan is presented.
    @State private var showingPlan = false
    /// Whether the grade simulator is presented.
    @State private var showingSimulator = false
    /// Whether the exam updates feed is presented.
    @State private var showingUpdates = false
    /// Which years are open. Nil until the student touches one, so the
    /// defaults below can depend on the data rather than on a first render.
    @State private var openYears: Set<String>?

    /// The page is the look's now, so its own colour is too. A fixed
    /// Politecnico navy on a page the student had coloured read as a screen
    /// borrowed from another app.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// Which list the picker is on.
    enum Scope: String, CaseIterable, Identifiable {
        /// The libretto, grouped by academic year.
        case libretto = "Libretto"
        /// The sittings, grouped by what is being asked of the student.
        case upcoming = "Appelli"
        /// The scope's identity, which is its title.
        var id: String { rawValue }
    }

    /// Shown inside a navigation stack that is not its own.
    private let embedded: Bool

    /// Creates the page.
    ///
    /// - Parameter embedded: True when a navigation stack already surrounds it, such as Cerca's or the panel's.
    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    /// The view's content.
    var body: some View {
        RootStack(embedded: embedded) {
            content(career)
                .safeAreaInset(edge: .top, spacing: 0) { FreshnessBar(age: career.age) }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { menu } }
                .navigationDestination(isPresented: $showingPlan) { StudyPlanView() }
                .navigationDestination(isPresented: $showingSimulator) { GradeSimulatorView() }
                .navigationDestination(isPresented: $showingUpdates) { ExamUpdatesView() }
                .task { await career.load() }
                .refreshable { await career.load(force: true) }
                .sheet(item: $selectedExam) { ExamDetailView(exam: $0) }
        }
    }

    // MARK: - The page

    /// The page itself: what expires, where the student is, and then the chosen list.
    ///
    /// - Parameter career: The career to draw.
    /// - Returns: The page.
    @ViewBuilder
    private func content(_ career: CareerModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LookTitle("Carriera", subtitle: planLine(career))

                if let message = career.errorMessage { errorBanner(message) }

                if style.special == .blueprint {
                    BlueprintDeadlines(deadlines: CareerDeadline.all(in: career.sessions)) { selectedExam = $0 }
                    if career.gradeBook != .empty || !career.libretto.isEmpty {
                        BlueprintStanding(book: career.gradeBook,
                                          mean: career.gradeBook.mean > 0 ? career.gradeBook.mean
                                              : StudyPlan(exams: career.libretto).weightedMean ?? 0,
                                          delta: career.meanDelta) { showingSimulator = true }
                        BlueprintPath(book: career.gradeBook, plan: { showingPlan = true },
                                      simulate: { showingSimulator = true }, updates: { showingUpdates = true })
                    }
                } else if style.special == .playful {
                    PlayfulTickets(deadlines: CareerDeadline.all(in: career.sessions)) { selectedExam = $0 }
                    if career.gradeBook != .empty || !career.libretto.isEmpty {
                        PlayfulStanding(book: career.gradeBook,
                                        mean: career.gradeBook.mean > 0 ? career.gradeBook.mean
                                            : StudyPlan(exams: career.libretto).weightedMean ?? 0,
                                        delta: career.meanDelta) { showingSimulator = true }
                        PlayfulPath(book: career.gradeBook, plan: { showingPlan = true },
                                    simulate: { showingSimulator = true }, updates: { showingUpdates = true })
                    }
                } else {
                    CareerNowCard(deadlines: CareerDeadline.all(in: career.sessions)) { selectedExam = $0 }

                    if career.gradeBook != .empty || !career.libretto.isEmpty {
                        CareerStandingCard(book: career.gradeBook, exams: career.libretto,
                                           delta: career.meanDelta) { showingSimulator = true }
                    }
                }

                // The libretto counts too: the three calls fail separately,
                // and a libretto that arrived must not be hidden behind
                // "nessun dato" because the other two did not.
                if career.gradeBook == .empty && career.sessions.isEmpty
                    && career.libretto.isEmpty && !career.isLoading {
                    unavailable(career)
                } else {
                    Picker("Sezione", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch scope {
                    case .libretto: libretto(career)
                    case .upcoming: upcoming(career)
                    }
                }
            }
            .padding()
            .padding(.bottom, 20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .overlay {
            if career.isLoading && career.sessions.isEmpty && career.libretto.isEmpty {
                ProgressView()
            }
        }
        .collapsingTitle("Carriera")
        .animation(.snappy(duration: 0.25), value: scope)
    }

    /// What the career is *of*, on the line above the title: the course, and
    /// the year of the plan where the header gives one.
    private func planLine(_ career: CareerModel) -> Text? {
        guard let header = career.planHeader else { return nil }
        let parts = [header.course?.capitalized, header.year].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return Text(verbatim: parts.joined(separator: " · "))
    }

    // MARK: - Toolbar

    /// The toolbar menu: the updates feed, the study plan and the simulator.
    private var menu: some View {
        Menu {
            Button("Novità", systemImage: "bell.badge") { showingUpdates = true }
            Section {
                Button("Piano di studi", systemImage: "list.bullet.rectangle") { showingPlan = true }
                Button("Simulazione media", systemImage: "function") { showingSimulator = true }
            }
        } label: {
            // The badge is on the tab already; here it is only the hint that
            // the menu is worth opening.
            Label("Altro", systemImage: feed.unreadCount > 0 ? "ellipsis.circle.fill" : "ellipsis.circle")
        }
        .accessibilityIdentifier("career-menu")
    }

    // MARK: - Libretto

    /// The libretto as one card per academic year, each opening on a tap.
    ///
    /// - Parameter career: The career to draw.
    /// - Returns: The list, or an empty state.
    @ViewBuilder
    private func libretto(_ career: CareerModel) -> some View {
        let groups = career.studyPlan.byYear
        if groups.isEmpty {
            ContentUnavailableView("Nessun esito", systemImage: "checkmark.seal",
                                   description: Text("Il libretto non ha restituito insegnamenti."))
                .padding(.top, 30)
        } else {
            VStack(spacing: 10) {
                ForEach(groups, id: \.year) { group in
                    LibrettoYearCard(title: group.year, exams: group.exams,
                                     isExpanded: isOpen(group.year, in: groups)) {
                        withAnimation(.snappy(duration: 0.28)) { toggle(group.year, in: groups) }
                    }
                }
            }
        }
    }

    /// Open by default: what is left to sit, and the year in progress. The
    /// rest is history, and history is what a disclosure is for.
    private func isOpen(_ year: String, in groups: [(year: String, exams: [LibrettoExam])]) -> Bool {
        if let openYears { return openYears.contains(year) }
        return year == StudyPlan.pendingGroup
            || year == groups.first(where: { $0.year != StudyPlan.pendingGroup })?.year
    }

    /// Opens or closes one year, taking over from the defaults on the first touch.
    ///
    /// - Parameters:
    ///   - year: The year to toggle.
    ///   - groups: Every year, for working out which were open by default.
    private func toggle(_ year: String, in groups: [(year: String, exams: [LibrettoExam])]) {
        var open = openYears ?? Set(groups.map(\.year).filter { isOpen($0, in: groups) })
        if open.contains(year) { open.remove(year) } else { open.insert(year) }
        openYears = open
    }

    // MARK: - Appelli

    /// The sittings grouped by what is being asked of the student, most urgent group first.
    ///
    /// - Parameter career: The career to draw.
    /// - Returns: The list, or an empty state.
    @ViewBuilder
    private func upcoming(_ career: CareerModel) -> some View {
        let sections = ExamAgenda.sections(from: career.sessions)
        if sections.isEmpty {
            ContentUnavailableView("Nessun appello", systemImage: "calendar.badge.clock",
                                   description: Text("Non ci sono appelli in programma."))
                .padding(.top, 30)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        LookHeading(verbatim: section.title)
                        ForEach(section.exams) { exam in
                            Button { selectedExam = exam } label: { ExamRow(exam: exam) }
                                .buttonStyle(.plain)
                        }
                        if let footnote = section.footnote {
                            Text(footnote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Nothing to show

    /// What the page says when there is no career to draw: the service's own answer where it gave one.
    ///
    /// - Parameter career: The career, read for why it is empty.
    /// - Returns: The empty state.
    @ViewBuilder
    private func unavailable(_ career: CareerModel) -> some View {
        if career.examServicesRefused {
            // What the server actually said, rather than a generic failure.
            // Signing in again returns the same answer, so offering that
            // would waste the user's time.
            ContentUnavailableView(
                "Servizi esami non abilitati",
                systemImage: "lock",
                description: Text("Il Politecnico risponde «Utente non abilitato» per il tuo profilo su iscrizione appelli e libretto. Di solito accade tra una sessione e l'altra o prima del rinnovo dell'iscrizione. Rifare l'accesso non cambia la risposta."))
                .padding(.top, 30)
        } else {
            ContentUnavailableView("Nessun dato di carriera", systemImage: "chart.bar",
                                   description: Text("I servizi del Politecnico non hanno restituito dati."))
                .padding(.top, 30)
        }
    }

    /// A failure said over the page that is still being shown.
    ///
    /// - Parameter message: What went wrong.
    /// - Returns: The banner.
    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.15), in: .rect(cornerRadius: 14))
            .foregroundStyle(.orange)
    }
}

// MARK: - Previews

#Preview("Carriera") {
    CareerView().previewEnvironment()
}

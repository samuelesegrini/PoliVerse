import SwiftUI

/// Tab-level entry point: pick a course, then see its materials.
struct WeBeepView: View {
    @Environment(CourseModel.self) private var courses
    @Environment(Session.self) private var session
    @Environment(WeBeepModel.self) private var weBeep

    @State private var showingLogin = false
    @State private var year: String?
    @State private var showingHidden = false
    @Environment(CareerModel.self) private var career
    @Environment(StudyProgrammeModel.self) private var programmes
    @Environment(CareersModel.self) private var careers
    @State private var originFilter: CourseOrigins.Filter = .all
    @State private var overrides = EnrolmentOverrides.all()

    /// Other careers' plans, read from their caches once rather than on
    /// every redraw.
    @State private var otherPlans: [EnrolmentOrigin.Plan] = []

    private var origins: CourseOrigins {
        CourseOrigins(student: session.student, career: career, programmes: programmes, otherPlans: otherPlans,
                      overrides: overrides, weBeep: weBeep)
    }

    /// WeBeep is the source of the course list, so when it is not connected the
    /// list is empty for a reason the user can actually fix — say so rather
    /// than showing a bare "no courses".
    private var needsLogin: Bool {
        !session.useMockData && !weBeep.isAuthenticated
    }

    @ViewBuilder
    private func row(_ course: Course, origin: EnrolmentOrigin) -> some View {
        NavigationLink(value: course) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.accent(for: course))
                    .frame(width: 6, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name).font(.subheadline.weight(.medium)).lineLimit(2)
                    Text([course.academicYear == "—" ? course.teacher : course.academicYear,
                          CourseOrigins.label(origin)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if course.isFavourite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button(course.isFavourite ? "Rimuovi" : "Preferito",
                   systemImage: course.isFavourite ? "star.slash" : "star") {
                courses.toggleFavourite(course)
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button("Nascondi", systemImage: "eye.slash", role: .destructive) {
                courses.toggleHidden(course)
            }
        }
        .contextMenu {
            // A guess from the study plans: the student can always correct it.
            Button("Del mio piano di studi", systemImage: "checkmark.seal") { setOverride(.plan, course) }
            Button("Iscrizione libera", systemImage: "hand.raised") { setOverride(.byChoice, course) }
            if overrides[course.id] != nil {
                Button("Deduci automaticamente", systemImage: "wand.and.stars") { setOverride(nil, course) }
            }
        }
    }

    private func setOverride(_ value: EnrolmentOrigin.Override?, _ course: Course) {
        EnrolmentOverrides.set(value, for: course.id)
        overrides = EnrolmentOverrides.all()
    }

    /// Shown inside a navigation stack that is not its own.
    private let embedded: Bool

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    var body: some View {
        RootStack(embedded: embedded) {
            List {
                if courses.academicYears.count > 1 {
                    Section {
                        YearFilter(years: courses.academicYears, selection: $year)
                            .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                }

                Section {
                    Picker("Mostra", selection: $originFilter) {
                        Text("Tutti").tag(CourseOrigins.Filter.all)
                        Text("Del piano").tag(CourseOrigins.Filter.plan)
                        if careers.hasChoice { Text("Altra carriera").tag(CourseOrigins.Filter.otherCareer) }
                        Text("Iscrizione libera").tag(CourseOrigins.Filter.byChoice)
                    }
                } footer: {
                    if originFilter != .all {
                        Text("Dedotto confrontando i corsi con il piano di studi di ogni tua matricola. Tieni premuto un corso per correggerlo.")
                    }
                }

                let origins = origins
                let shown = origins.filter(courses.courses(in: year), by: originFilter)
                let favourites = shown.filter(\.isFavourite)
                let others = shown.filter { !$0.isFavourite }

                if !favourites.isEmpty {
                    Section("Preferiti") {
                        ForEach(favourites) { row($0, origin: origins.origin(of: $0)) }
                    }
                }

                Section(favourites.isEmpty ? "" : "Altri corsi") {
                    ForEach(others) { row($0, origin: origins.origin(of: $0)) }
                }

                if !courses.hiddenOnly.isEmpty {
                    Section {
                        Button {
                            showingHidden = true
                        } label: {
                            Label("Corsi nascosti (\(courses.hiddenOnly.count))",
                                  systemImage: "eye.slash")
                        }
                    }
                }
            }
            .navigationTitle("WeBeep")
            .navigationDestination(for: Course.self) { CourseMaterialsView(course: $0) }
            .task {
                await CourseOrigins.load(courses: courses, careers: careers, career: career, programmes: programmes,
                                         weBeep: weBeep, student: session.student) { otherPlans = $0 }
            }
            .overlay {
                if needsLogin {
                    ContentUnavailableView {
                        Label("Collega WeBeep", systemImage: "books.vertical")
                    } description: {
                        Text("WeBeep usa un accesso separato da quello dei servizi d'ateneo. Serve una sola volta.")
                    } actions: {
                        Button("Accedi a WeBeep") { showingLogin = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if courses.courses.isEmpty && !courses.isLoading {
                    ContentUnavailableView("Nessun corso", systemImage: "books.vertical",
                                           description: Text("Non risultano corsi attivi su WeBeep."))
                }
            }
            .sheet(isPresented: $showingLogin) {
                // Forced: connecting WeBeep is exactly the moment the held
                // course list stopped being right.
                WeBeepLoginSheet { await courses.load(force: true) }
            }
            .sheet(isPresented: $showingHidden) {
                NavigationStack {
                    List(courses.hiddenOnly) { course in
                        HStack {
                            Text(course.name).font(.subheadline)
                            Spacer()
                            Button("Mostra") { courses.toggleHidden(course) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .navigationTitle("Corsi nascosti")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { showingHidden = false }
                        }
                    }
                    .overlay {
                        if courses.hiddenOnly.isEmpty {
                            ContentUnavailableView("Nessun corso nascosto",
                                                   systemImage: "eye")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("WeBeep") {
    WeBeepView().previewEnvironment()
}

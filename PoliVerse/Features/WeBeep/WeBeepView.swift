import SwiftUI

/// Tab-level entry point: pick a course, then see its materials.
struct WeBeepView: View {
    @Environment(CourseService.self) private var courses
    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep

    @State private var showingLogin = false
    @State private var year: String?
    @State private var showingHidden = false
    @Environment(CareerService.self) private var career
    @Environment(StudyProgrammeService.self) private var programmes
    @Environment(CareersService.self) private var careers
    @State private var originFilter: OriginFilter = .all
    @State private var overrides = EnrolmentOverrides.all()

    enum OriginFilter: Hashable {
        case all, plan, otherCareer, byChoice
    }

    /// Other careers' plans, read from their caches once rather than on
    /// every redraw.
    @State private var otherPlans: [EnrolmentOrigin.Plan] = []

    private var plans: [EnrolmentOrigin.Plan] {
        // The libretto, and the teachings of the plan pages read for this
        // career: a course of the plan counts even before the libretto lists it.
        let current = EnrolmentOrigin.Plan(matricola: session.student?.matricola ?? "", isCurrent: true,
                                           libretto: career.libretto)
        return [EnrolmentOrigin.Plan(matricola: current.matricola, isCurrent: true,
                                     codes: current.codes.union(programmes.planCodes),
                                     names: Set(career.libretto.map(\.name)))] + otherPlans
    }

    private func origin(_ course: Course, plans: [EnrolmentOrigin.Plan]) -> EnrolmentOrigin {
        let moodle = course.moodleID.flatMap(weBeep.moodleCourse(id:))
        return EnrolmentOrigin.classify(
            codes: EnrolmentOrigin.codes(in: [course.teachingCode, moodle?.idnumber, moodle?.shortname]),
            name: course.name, plans: plans, override: overrides[course.id],
            selfEnrolmentOpen: course.moodleID.flatMap { weBeep.selfEnrolment[$0] })
    }

    private func filtered(_ list: [Course]) -> [Course] {
        guard originFilter != .all else { return list }
        let plans = plans
        return list.filter { course in
            switch (origin(course, plans: plans), originFilter) {
            case (.currentPlan, .plan), (.otherCareer, .otherCareer), (.outsidePlan, .byChoice), (.selfEnrolled, .byChoice): true
            default: false
            }
        }
    }

    private func originLabel(_ origin: EnrolmentOrigin) -> String? {
        switch origin {
        case .currentPlan, .unknown: nil
        case .otherCareer(let matricola): String(localized: "Piano della matricola \(matricola)")
        case .outsidePlan: String(localized: "Fuori dal piano di studi")
        case .selfEnrolled: String(localized: "Probabile iscrizione libera")
        }
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
                          originLabel(origin)].compactMap { $0 }.joined(separator: " · "))
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

    var body: some View {
        NavigationStack {
            List {
                if courses.academicYears.count > 1 {
                    Section {
                        YearFilter(years: courses.academicYears, selection: $year)
                            .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                }

                Section {
                    Picker("Mostra", selection: $originFilter) {
                        Text("Tutti").tag(OriginFilter.all)
                        Text("Del piano").tag(OriginFilter.plan)
                        if careers.hasChoice { Text("Altra carriera").tag(OriginFilter.otherCareer) }
                        Text("Iscrizione libera").tag(OriginFilter.byChoice)
                    }
                } footer: {
                    if originFilter != .all {
                        Text("Dedotto confrontando i corsi con il piano di studi di ogni tua matricola. Tieni premuto un corso per correggerlo.")
                    }
                }

                let plans = plans
                let favourites = filtered(courses.courses(in: year)).filter(\.isFavourite)
                let others = filtered(courses.courses(in: year)).filter { !$0.isFavourite }

                if !favourites.isEmpty {
                    Section("Preferiti") {
                        ForEach(favourites) { row($0, origin: origin($0, plans: plans)) }
                    }
                }

                Section(favourites.isEmpty ? "" : "Altri corsi") {
                    ForEach(others) { row($0, origin: origin($0, plans: plans)) }
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
                await courses.load()
                await careers.load()
                let current = session.student?.matricola
                otherPlans = careers.careers.filter { $0.matricola != current }.compactMap { other in
                    CareerService.cachedLibretto(account: other.matricola).map {
                        EnrolmentOrigin.Plan(matricola: other.matricola, isCurrent: false, libretto: $0)
                    }
                }
                await career.load()
                // The plan of every year the list covers, so its courses read
                // as "del piano" by the plan itself, not only by the libretto.
                await programmes.prepare()
                for year in Set(courses.courses.compactMap(\.academicYearStart)) {
                    _ = await programmes.plan(forYear: year)
                }
                // Only pages outside every plan need asking how they enrol.
                let plans = plans
                let unplanned = courses.courses.filter {
                    if case .outsidePlan = origin($0, plans: plans) { return true }
                    return false
                }.compactMap(\.moodleID)
                await weBeep.loadSelfEnrolment(for: unplanned)
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

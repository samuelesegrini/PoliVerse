import CoreSpotlight
import SwiftUI

/// One field over everything the app already holds, drawn as the course pages
/// are: the look's sheet, glass for what can be touched.
///
/// Before a search the page is a way in: the searches made lately as glass
/// chips, and the places that are not tabs as a grid of glass tiles. While
/// typing, the kinds of result are **search tokens** rather than scopes — tap
/// "Aule" among the suggestions and it sits in the field beside the text, the
/// way Mail and Photos narrow a search — and the best single match is lifted
/// above the rest, one panel with its symbol, so the answer to most searches
/// is the first thing on screen. Each kind below shows three results, with the
/// rest one tap away.
///
/// Deliberately searches what is **in memory**, never the network: a search
/// box that pauses to fetch is a search box nobody uses. That shapes what is
/// findable — WeBeep materials are searched across the courses already opened,
/// because reaching the rest would mean 22 requests per keystroke, and the
/// materials say so rather than leaving the gap to be discovered.
struct SearchView: View {
    /// The shared ``CourseModel``, from the environment.
    @Environment(CourseModel.self) private var courses
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``RoomsModel``, from the environment.
    @Environment(RoomsModel.self) private var rooms
    /// The shared ``NewsModel``, from the environment.
    @Environment(NewsModel.self) private var news
    /// The shared ``NoticeModel``, from the environment.
    @Environment(NoticeModel.self) private var notices
    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// The look in use, which the tiles' colour and typeface come from.
    @Environment(\.colorScheme) private var scheme
    @Environment(\.look) private var style
    /// The latest searches, newest first, one per line.
    @AppStorage("searchRecents") private var storedRecents = ""

    /// What the student is typing, updated on every keystroke.
    @State private var query = ""
    /// The kinds the search has been narrowed to. Empty means every kind.
    @State private var debouncedQuery = ""
    @State private var tokens: [Kind] = []
    @State private var expanded: Set<Kind> = []
    @State private var selectedEvent: AgendaEvent?
    @State private var selectedExam: ExamSession?
    @State private var spotlightCourse: Course?
    @State private var spotlightRoom: Classroom?
    @State private var spotlightTeacher: Teacher?

    /// A kind of result, which is also a token that narrows the search to it.
    nonisolated enum Kind: String, CaseIterable, Identifiable, Hashable {
        /// The eight kinds of result, in the order they are shown.
        case courses, teachers, rooms, exams, calendar, materials, news, notices
        /// The raw value.
        var id: String { rawValue }

        /// The kind's name on screen, which is also its token's label.
        var title: String {
            switch self {
            case .courses: String(localized: "Corsi")
            case .teachers: String(localized: "Docenti")
            case .rooms: String(localized: "Aule")
            case .exams: String(localized: "Appelli")
            case .calendar: String(localized: "In calendario")
            case .materials: String(localized: "Materiali")
            case .news: String(localized: "Notizie")
            case .notices: String(localized: "Notifiche")
            }
        }

        /// The SF Symbol for the kind.
        var symbol: String {
            switch self {
            case .courses: "books.vertical"
            case .teachers: "person"
            case .rooms: "door.left.hand.open"
            case .exams: "pencil.and.list.clipboard"
            case .calendar: "calendar"
            case .materials: "folder"
            case .news: "newspaper"
            case .notices: "megaphone"
            }
        }
    }

    /// The settled query, trimmed, which every match is made against.
    private var trimmed: String {
        debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether there is anything to search for, which decides between the browse and results
    /// views.
    private var isSearching: Bool { !trimmed.isEmpty }

    /// Whether a kind is being searched.
    ///
    /// - Parameter kind: The kind to check.
    /// - Returns: `true` when no token narrows the search, or when this kind is one of them.
    private func shows(_ kind: Kind) -> Bool {
        tokens.isEmpty || tokens.contains(kind)
    }

    /// The latest searches, newest first.
    private var recents: [String] {
        storedRecents.split(separator: "\n").map(String.init)
    }

    /// Records a search, moving a repeat to the front and keeping the latest eight. Anything
    /// shorter than two characters is ignored.
    ///
    /// - Parameter search: What the student searched for.
    private func remember(_ search: String) {
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard search.count >= 2 else { return }
        let kept = [search] + recents.filter { $0.caseInsensitiveCompare(search) != .orderedSame }
        storedRecents = kept.prefix(8).joined(separator: "\n")
    }

    // MARK: - Matching

    /// Courses matching the query by name, lecturer, code or academic year, best first.
    private var matchedCourses: [Course] {
        guard isSearching, shows(.courses) else { return [] }
        return SearchMatch.rank(courses.courses, query: trimmed) {
            [$0.name, $0.teacher, $0.code ?? "", $0.academicYear]
        }
    }

    /// Agenda entries matching the query by title or room.
    private var matchedEvents: [AgendaEvent] {
        guard isSearching, shows(.calendar) else { return [] }
        let upcoming = agenda.events.filter { $0.end > .now }
        return Array(SearchMatch.rank(upcoming, query: trimmed) {
            [$0.title, $0.room ?? "", $0.roomAcronym ?? ""]
        }.prefix(10))
    }

    /// Exam sittings matching the query by teaching, lecturer or room.
    private var matchedExams: [ExamSession] {
        guard isSearching, shows(.exams) else { return [] }
        return SearchMatch.rank(career.sessions, query: trimmed) {
            [$0.courseName, $0.room ?? "", $0.teacher ?? ""]
        }
    }

    /// Rooms matching the query by code, building or campus.
    private var matchedRooms: [Classroom] {
        guard trimmed.count >= 2, shows(.rooms) else { return [] }
        return Array(SearchMatch.rank(rooms.rooms, query: trimmed) {
            [$0.id, $0.buildingName ?? "", $0.campusName ?? "", $0.address ?? ""]
        }.prefix(8))
    }

    /// Lecturers matching the query by name or address.
    private var matchedTeachers: [Teacher] {
        guard trimmed.count >= 2, shows(.teachers) else { return [] }
        let roster = Teacher.roster(courses: courses.courses, sessions: career.sessions)
        return Array(SearchMatch.rank(roster, query: trimmed) {
            [$0.name, $0.email ?? ""]
        }.prefix(8))
    }

    /// News items matching the query by title or summary.
    private var matchedNews: [NewsItem] {
        guard trimmed.count >= 2, shows(.news) else { return [] }
        return Array(SearchMatch.rank(news.items, query: trimmed) {
            [$0.title, $0.summary ?? "", $0.category ?? ""]
        }.prefix(6))
    }

    /// Notifications matching the query by title or text.
    private var matchedNotices: [Notice] {
        guard trimmed.count >= 2, shows(.notices) else { return [] }
        return Array(SearchMatch.rank(notices.notices, query: trimmed) {
            [$0.title, $0.body ?? "", $0.category ?? ""]
        }.prefix(6))
    }

    /// WeBeep files matching the query by name, among those already listed for a course.
    private var matchedFiles: [WeBeepFile] {
        guard trimmed.count >= 2, shows(.materials) else { return [] }
        return Array(SearchMatch.rank(weBeep.sections.flatMap(\.files), query: trimmed) {
            [$0.name, $0.sectionName]
        }.prefix(8))
    }

    /// Every result as one shape, grouped by kind in the order they are shown.
    ///
    /// Cached in `results` rather than computed inline: `resultsContent` is
    /// now always in the view tree (see `body`), so a plain computed property
    /// here would re-run all eight ranking passes on every keystroke, not
    /// just when the settled query changes.
    @State private var results: [(kind: Kind, items: [Result])] = []

    /// Runs every match and groups what they found.
    ///
    /// - Returns: The non-empty groups, in the order they are shown.
    private func computeResults() -> [(kind: Kind, items: [Result])] {
        let groups: [(Kind, [Result])] = [
            (.courses, matchedCourses.map(Result.course)),
            (.teachers, matchedTeachers.map(Result.teacher)),
            (.rooms, matchedRooms.map(Result.room)),
            (.exams, matchedExams.map(Result.exam)),
            (.calendar, matchedEvents.map(Result.event)),
            (.materials, matchedFiles.map(Result.file)),
            (.news, matchedNews.map(Result.news)),
            (.notices, matchedNotices.map(Result.notice)),
        ]
        return groups.filter { !$0.1.isEmpty }.map { (kind: $0.0, items: $0.1) }
    }

    /// Recomputes the cached results, which the settled query and the tokens both trigger.
    private func refreshResults() { results = computeResults() }

    /// The single match most likely to be what was meant: a name that starts
    /// with the query beats one that only contains it, and people, places and
    /// courses beat dated things, which are many.
    private func topHit(in results: [(kind: Kind, items: [Result])]) -> Result? {
        let order: [Kind] = [.courses, .teachers, .rooms, .exams, .calendar, .news, .notices, .materials]
        let all = order.flatMap { kind in results.first { $0.kind == kind }?.items ?? [] }
        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return all.first {
            $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).hasPrefix(folded)
        } ?? all.first
    }

    // MARK: - Body

    /// Shown inside a navigation stack that is not its own.
    private let embedded: Bool
    /// The new interface's places, listed before a search in place of the
    /// map and the plan; nil in the current interface.
    private let places: [NewDestination]?

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - embedded: `true` when it is already inside a navigation stack.
    ///   - places: The destinations to offer before a search, or `nil` to offer none.
    init(embedded: Bool = false, places: [NewDestination]? = nil) {
        self.embedded = embedded
        self.places = places
    }

    /// The view's content.
    var body: some View {
        RootStack(embedded: embedded) {
            ScrollView {
                // Both branches stay mounted and only trade opacity: an
                // if/else here swaps two structurally different subtrees,
                // which Instruments caught as a main-thread hang (allocating
                // and tearing down the whole browse or results tree) the
                // moment a search starts.
                ZStack(alignment: .top) {
                    // Each branch wrapped in its own VStack: `browseContent`
                    // and `resultsContent` are `@ViewBuilder`s returning
                    // several sibling sections, and a bare ZStack overlays
                    // sibling views instead of stacking them — every section
                    // rendered on top of the others at the same position.
                    VStack(alignment: .leading, spacing: 26) { browseContent }
                        .opacity(isSearching ? 0 : 1)
                        .allowsHitTesting(!isSearching)
                    VStack(alignment: .leading, spacing: 26) { resultsContent }
                        .opacity(isSearching ? 1 : 0)
                        .allowsHitTesting(isSearching)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: trimmed)
                .animation(.snappy, value: tokens)
            }
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("search-list")
            .navigationTitle("Cerca")
            // The page's own title says "Cerca": the bar keeps it only as the
            // back button's label.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Text(verbatim: "") } }
            // Donated so the screen can be handed off and offered as a
            // suggestion. The query travels with it; nothing else does.
            .userActivity(SpotlightIndex.activityType) { activity in
                activity.title = trimmed.isEmpty ? "Cerca in PoliVerse" : "Cerca “\(trimmed)”"
                activity.isEligibleForHandoff = true
                activity.isEligibleForPrediction = true
                activity.userInfo = ["query": trimmed]
            }
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .navigationDestination(for: NewDestination.self) { $0.screen }
            // Tokens are added from the page's own chips, not the system's
            // suggested-token list: that list covers the page the moment the
            // tab opens the field, hiding the recents and places under it.
            .searchable(text: $query, tokens: $tokens,
                        prompt: Text("Corsi, docenti, aule, notizie, materiali")) { kind in
                Label(kind.title, systemImage: kind.symbol)
            }
            .onSubmit(of: .search) { remember(trimmed) }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .sheet(item: $selectedEvent) { EventDetailView(event: $0) }
            .sheet(item: $selectedExam) { ExamDetailView(exam: $0) }
            .navigationDestination(item: $spotlightRoom) { ClassroomDetailView(room: $0) }
            .navigationDestination(item: $spotlightTeacher) { TeacherDetailView(teacher: $0) }
            // A Spotlight hit lands here: the identifier says which screen,
            // and the object is looked up in what is already loaded.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard
                    let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                    let item = SpotlightIndex.Item(identifier: id)
                else { return }
                open(item)
            }
            .navigationDestination(item: $spotlightCourse) { CourseDetailView(course: $0) }
            .task(id: query) {
                let settled = query
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                debouncedQuery = settled
                refreshResults()
            }
            .onChange(of: tokens) { refreshResults() }
            .task {
                await rooms.load()
                await courses.load()
                await agenda.load(around: .now)
                await career.load()
                // Cheap and already-windowed, so searching them costs nothing
                // at the keystroke.
                await news.load()
                await notices.load()
                // The searches above can finish after a query already
                // settled (e.g. typing while cold), which would otherwise
                // leave `results` stuck on a stale, thinner answer.
                refreshResults()
            }
        }
    }

    // MARK: - Before a search

    /// What is shown before a search. In the new interface: the searches
    /// made lately, then the places and people that are Cerca's — the campus,
    /// the teachers — and what comes from the Politecnico. The kinds of result
    /// are chips over the results instead, with their counts, where they say
    /// something. The current interface keeps its page of kinds and places.
    @ViewBuilder
    private var browseContent: some View {
        LookTitle("Cerca")

        if places != nil {
            switch style.special {
            case .playful: PlayfulSearchHero()
            case .blueprint: BlueprintSearchHero()
            case nil:
                campusSection
                teachersSection
            }
            recentsSection
            politecnicoSection
        } else {
            legacyBrowseContent
        }
    }

    /// The current interface's page before a search: the kinds, the recent
    /// searches, and every place as a tile.
    @ViewBuilder
    private var legacyBrowseContent: some View {
        kindChips

        recentsSection

        VStack(alignment: .leading, spacing: 10) {
            LookHeading("Vai a")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                if let places {
                    ForEach(places) { place in
                        NavigationLink(value: place) {
                            PlaceTile(title: Text(place.title), detail: Text(place.detail), symbol: place.systemImage,
                                      colour: colour(for: place.systemImage))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("place-\(place.id)")
                    }
                }
                NavigationLink { RoomsView() } label: {
                    PlaceTile(title: Text("Aule"), detail: Text("Tutte le aule del campus"), symbol: "building.2",
                              colour: colour(for: "building.2"))
                }
                .buttonStyle(.plain)
                if places == nil {
                    NavigationLink { CampusMapView() } label: {
                        PlaceTile(title: Text("Mappa del campus"), detail: Text("Campus ed edifici"), symbol: "map",
                                  colour: colour(for: "map"))
                    }
                    .buttonStyle(.plain)
                    NavigationLink { StudyPlanView() } label: {
                        PlaceTile(title: Text("Piano di studi"), detail: Text("Piano e simulazione"),
                                  symbol: "list.bullet.rectangle", colour: colour(for: "list.bullet.rectangle"))
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink { ManifestiView() } label: {
                    PlaceTile(title: Text("Manifesto"), detail: Text("Corsi di studi e schede"), symbol: "books.vertical",
                              colour: colour(for: "books.vertical"))
                }
                .buttonStyle(.plain)
                NavigationLink { PersonalTimetableView() } label: {
                    PlaceTile(title: Text("Orario personalizzato"), detail: Text("Scegli i tuoi scaglioni"),
                              symbol: "calendar.badge.plus", colour: colour(for: "calendar.badge.plus"))
                }
                .buttonStyle(.plain)
                NavigationLink { GradeSimulatorView() } label: {
                    PlaceTile(title: Text("Simulazione media"), detail: Text("Prova i voti che verranno"),
                              symbol: "function", colour: colour(for: "function"))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The searches made lately, as chips that put the search back.
    @ViewBuilder
    private var recentsSection: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                LookHeading("Recenti") {
                    Button("Cancella") { withAnimation(.snappy) { storedRecents = "" } }
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(recents, id: \.self) { recent in
                                Button { query = recent } label: {
                                    Label(recent, systemImage: "clock.arrow.circlepath")
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .contentShape(.capsule)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 2)
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -20)
            }
        }
    }

    /// The campus: rooms free now, the map, and every room.
    private var campusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading("Campus")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach([NewDestination.freeRooms, .map]) { place in
                    NavigationLink(value: place) {
                        PlaceTile(title: Text(place.title), detail: Text(place.detail), symbol: place.systemImage,
                                  colour: colour(for: place.systemImage))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("place-\(place.id)")
                }
                NavigationLink { RoomsView() } label: {
                    PlaceTile(title: Text("Aule"), detail: Text("Tutte le aule del campus"), symbol: "building.2",
                              colour: colour(for: "building.2"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("place-rooms")
            }
        }
    }

    /// The student's teachers, each a way to their page.
    @ViewBuilder
    private var teachersSection: some View {
        let roster = Array(Teacher.roster(courses: courses.courses, sessions: career.sessions).prefix(8))
        if !roster.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                LookHeading("I tuoi docenti")
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(roster) { teacher in
                            NavigationLink { TeacherDetailView(teacher: teacher) } label: {
                                TeacherBadge(teacher: teacher)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -20)
            }
        }
    }

    /// What comes from the Politecnico: news, and the notifications addressed to the student.
    private var politecnicoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading("Dal Politecnico")
            VStack(spacing: 0) {
                ForEach([NewDestination.news, .notices]) { place in
                    NavigationLink(value: place) {
                        HStack(spacing: 12) {
                            CourseRowTile(symbol: place.systemImage, colour: colour(for: place.systemImage))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.title).font(.subheadline)
                                Text(place.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 11)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("place-\(place.id)")
                    if place == .news { Divider().padding(.leading, 42) }
                }
            }
            .padding(.horizontal, 16)
            .lookCard()
        }
    }

    /// The kinds of result as glass chips: a tap narrows the search to that
    /// kind, and the token appears in the field.
    private var kindChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading("Cerca tra")
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Kind.allCases) { kind in
                            let on = tokens.contains(kind)
                            Button {
                                withAnimation(.snappy) {
                                    if on { tokens.removeAll { $0 == kind } } else { tokens.append(kind) }
                                }
                            } label: {
                                Label(kind.title, systemImage: kind.symbol)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(on ? .regular.tint(style.accent(scheme).opacity(0.25)).interactive()
                                            : .regular.interactive(), in: .capsule)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }

    /// The kinds that found something, as chips with their counts over the
    /// results: Tutto, then each kind, a tap narrowing the search to it — the
    /// token appears in the field, as it would chosen there.
    private func resultChips(_ results: [(kind: Kind, items: [Result])]) -> some View {
        let total = results.reduce(0) { $0 + $1.items.count }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                LookChip(title: Text("Tutto \(total)"), isOn: tokens.isEmpty) {
                    withAnimation(.snappy) { tokens = [] }
                }
                .accessibilityIdentifier("search-chip-all")
                ForEach(results, id: \.kind) { group in
                    let on = tokens.contains(group.kind)
                    LookChip(title: Text("\(group.kind.title) \(group.items.count)"), isOn: on,
                             systemImage: group.kind.symbol) {
                        withAnimation(.snappy) { tokens = on ? [] : [group.kind] }
                    }
                    .accessibilityIdentifier("search-chip-\(group.kind.rawValue)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }

    /// A colour of the look's ramp for a place, stable for its symbol.
    private func colour(for symbol: String) -> Flavor.RGB {
        FlavorRamp(style: style, scheme: scheme).colour(at: Double(TodayDigest.colourIndex(for: symbol)) / 7)
    }

    // MARK: - Results

    /// The results: the top hit above, then one group per kind, each expandable past its first
    /// few rows.
    @ViewBuilder
    private var resultsContent: some View {
        let results = results
        if !results.isEmpty || !tokens.isEmpty {
            resultChips(results)
        }
        if results.isEmpty {
            ContentUnavailableView.search(text: trimmed)
                .padding(.top, 40)
                .accessibilityIdentifier("search-empty")
            // The search only reads what the app holds: say where else the
            // thing might be, rather than leaving a dead end.
            VStack(alignment: .leading, spacing: 10) {
                LookHeading("Cerca anche in")
                NavigationLink { ManifestiView() } label: {
                    HStack(spacing: 12) {
                        CourseRowTile(symbol: "books.vertical", colour: colour(for: "books.vertical"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manifesto degli studi").font(.subheadline)
                            Text("Gli insegnamenti di tutti i corsi di laurea").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .lookCard()
                .accessibilityIdentifier("search-empty-manifesti")
            }
        } else {
            if let hit = topHit(in: results) {
                VStack(alignment: .leading, spacing: 10) {
                    LookHeading("Migliore corrispondenza")
                    resultLink(hit) { TopHitPanel(result: hit, query: trimmed, colour: colour(for: hit.kind.symbol)) }
                }
            }
            ForEach(results, id: \.kind) { group in
                let all = tokens.contains(group.kind) || expanded.contains(group.kind)
                let shown = all ? group.items : Array(group.items.prefix(3))
                VStack(alignment: .leading, spacing: 10) {
                    LookHeading(verbatim: group.kind.title) {
                        if group.items.count > 3 && !tokens.contains(group.kind) {
                            Button(all ? "Meno" : "Tutti (\(group.items.count))") {
                                withAnimation(.snappy) {
                                    if all { expanded.remove(group.kind) } else { expanded.insert(group.kind) }
                                }
                            }
                            .foregroundStyle(.tint)
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(shown) { result in
                            resultLink(result) {
                                ResultRow(result: result, query: trimmed, colour: colour(for: result.kind.symbol),
                                          last: result.id == shown.last?.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .lookCard()
                    if group.kind == .materials {
                        Text("Solo i corsi WeBeep già aperti: cercarli tutti richiederebbe una richiesta per corso.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    /// A result as whatever opens it: a push, a sheet, or nothing for a file.
    @ViewBuilder
    private func resultLink(_ result: Result, @ViewBuilder label: () -> some View) -> some View {
        switch result {
        case .course(let course):
            NavigationLink(value: course) { label() }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { remember(trimmed) })
        case .teacher(let teacher):
            NavigationLink { TeacherDetailView(teacher: teacher) } label: { label() }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { remember(trimmed) })
        case .room(let room):
            NavigationLink { ClassroomDetailView(room: room) } label: { label() }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { remember(trimmed) })
        case .exam(let exam):
            Button { remember(trimmed); selectedExam = exam } label: { label() }
                .buttonStyle(.plain)
        case .event(let event):
            Button { remember(trimmed); selectedEvent = event } label: { label() }
                .buttonStyle(.plain)
        case .news(let item):
            NavigationLink { NewsDetailView(item: item) } label: { label() }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { remember(trimmed) })
        case .notice(let notice):
            NavigationLink { NoticeDetailView(notice: notice) } label: { label() }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { remember(trimmed) })
        case .file:
            label()
        }
    }

    /// Routes a Spotlight identifier to a screen.
    ///
    /// Looks the object up in what is loaded rather than refetching: the index
    /// can outlive the data by a month, and a hit on something no longer in
    /// the plan should quietly do nothing rather than spin.
    private func open(_ item: SpotlightIndex.Item) {
        switch item {
        case .course(let id):
            spotlightCourse = courses.courses.first { $0.id == id }
        case .room(let id):
            spotlightRoom = rooms.rooms.first { $0.id == id }
        case .teacher(let id):
            spotlightTeacher = Teacher
                .roster(courses: courses.courses, sessions: career.sessions)
                .first { $0.id == id }
        case .exam:
            // Exams have no screen of their own from here; the query is left
            // showing the career tab's own list instead.
            break
        }
    }
}

// MARK: - Results as one shape

/// Any result, with the words and symbol a row needs.
private enum Result: Identifiable {
    /// A course, a lecturer, a room or an exam sitting.
    case course(Course), teacher(Teacher), room(Classroom), exam(ExamSession)
    /// An agenda entry, a WeBeep file, a news item or a notification.
    case event(AgendaEvent), file(WeBeepFile), news(NewsItem), notice(Notice)

    /// The kind and the thing's own identifier, so two kinds cannot collide.
    var id: String {
        switch self {
        case .course(let course): "course-\(course.id)"
        case .teacher(let teacher): "teacher-\(teacher.id)"
        case .room(let room): "room-\(room.id)"
        case .exam(let exam): "exam-\(exam.id)"
        case .event(let event): "event-\(event.id)"
        case .file(let file): "file-\(file.id)"
        case .news(let item): "news-\(item.id)"
        case .notice(let notice): "notice-\(notice.id)"
        }
    }

    /// Which group this result belongs to.
    var kind: SearchView.Kind {
        switch self {
        case .course: .courses
        case .teacher: .teachers
        case .room: .rooms
        case .exam: .exams
        case .event: .calendar
        case .file: .materials
        case .news: .news
        case .notice: .notices
        }
    }

    /// The result's name, which is what the query is highlighted in.
    var title: String {
        switch self {
        case .course(let course): course.name
        case .teacher(let teacher): teacher.name
        case .room(let room): room.id
        case .exam(let exam): exam.courseName
        case .event(let event): event.title
        case .file(let file): file.name
        case .news(let item): item.title
        case .notice(let notice): notice.title
        }
    }

    /// The symbol of the thing itself: a course's subject, a file's type.
    var symbol: String {
        switch self {
        case .course(let course): SubjectSymbol.symbol(for: course.name)
        case .exam(let exam): SubjectSymbol.symbol(for: exam.courseName)
        case .event(let event): event.kind.icon
        case .file(let file): file.icon
        default: kind.symbol
        }
    }

    /// The second line: what the thing is, or when.
    ///
    /// - Parameter locale: The locale dates are formatted in. Passed explicitly because
    ///   `Date.formatted` reads `Locale.current` rather than the SwiftUI environment.
    /// - Returns: The line, or `nil` when there is nothing to add.
    @MainActor
    func detail(locale: Locale) -> String? {
        switch self {
        case .course(let course):
            return [course.teacher == "—" ? nil : course.teacher, course.academicYear == "—" ? nil : course.academicYear]
                .compactMap { $0 }.joined(separator: " · ").nonEmpty
        case .teacher(let teacher):
            return teacher.courses.isEmpty ? teacher.email : String(localized: "\(teacher.courses.count) insegnamenti")
        case .room(let room):
            return room.locationLabel.isEmpty ? String(localized: "\(room.capacity) posti")
                : String(localized: "\(room.locationLabel) · \(room.capacity) posti")
        case .exam(let exam):
            return exam.grade.map { String(localized: "Esito: \($0.display)") }
                ?? exam.date?.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
                ?? exam.status.label
        case .event(let event):
            return "\(event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))) · \(event.start.formatted(.dateTime.hour().minute().locale(locale)))"
        case .file(let file):
            return file.sectionName
        case .news(let item):
            return item.displayDate?.formatted(.relative(presentation: .named).locale(locale))
        case .notice(let notice):
            return notice.date?.formatted(.relative(presentation: .named).locale(locale))
        }
    }
}

/// The text with the query's words set in the primary colour and bold, the
/// rest left as it is: where the match is reads at a glance.
private func highlighted(_ text: String, query: String) -> AttributedString {
    var attributed = AttributedString(text)
    for word in SearchMatch.words(in: query) {
        var searchStart = text.startIndex
        while let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                     range: searchStart..<text.endIndex) {
            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
            }
            searchStart = range.upperBound
        }
    }
    return attributed
}

// MARK: - Pieces

/// A place as a glass tile: its symbol in the look's colour, a name and what
/// is there.
/// Also drawn by the onboarding tour's Cerca card.
struct PlaceTile: View {
    /// The place's name.
    let title: Text
    /// What is there.
    let detail: Text
    /// The SF Symbol for the place.
    let symbol: String
    /// The look's colour, which the symbol is drawn in.
    let colour: Flavor.RGB

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(colour.color)
                .frame(height: 30)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .contentShape(.rect)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .accessibilityElement(children: .combine)
    }
}

/// A teacher as a disc with their initials in their first course's colour,
/// and their surname under it.
private struct TeacherBadge: View {
    /// The teacher.
    let teacher: Teacher

    /// The view's content.
    var body: some View {
        let colour = Theme.courseAccents[TodayDigest.colourIndex(for: teacher.courses.first?.name ?? teacher.name)]
        let words = teacher.name.split(separator: " ")
        VStack(spacing: 6) {
            Text(words.prefix(2).compactMap(\.first).map(String.init).joined())
                .font(.headline)
                .foregroundStyle(Theme.onAccent)
                .frame(width: 54, height: 54)
                .background(colour, in: .circle)
            Text(words.last.map(String.init) ?? teacher.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 70)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(teacher.name))
    }
}

/// The best match, lifted above the rest: its symbol on a glass tile, the
/// name large, and what it is.
private struct TopHitPanel: View {
    /// The best match.
    let result: Result
    /// What was searched for, which is shown in bold within the title.
    let query: String
    /// The look's colour, which the tile is drawn in.
    let colour: Flavor.RGB

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    @Environment(\.look) private var style

    /// The view's content.
    var body: some View {
        HStack(spacing: 16) {
            GlassTile(symbol: result.symbol, colour: colour, side: 64, surface: .glass,
                      mode: style.appearance.flavorMode)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.kind.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
                Text(highlighted(result.title, query: query))
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let detail = result.detail(locale: locale) {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .lookCard(cornerRadius: 26)
        .accessibilityElement(children: .combine)
    }
}

/// One result: its symbol, the name with the match in bold, and what it is.
private struct ResultRow: View {
    /// The result this row shows.
    let result: Result
    /// What was searched for, which is shown in bold within the title.
    let query: String
    /// The look's colour, which the symbol is drawn in.
    let colour: Flavor.RGB
    /// Whether this is the last row of its card, which draws no hairline.
    let last: Bool

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CourseRowTile(symbol: result.symbol, colour: colour)
                VStack(alignment: .leading, spacing: 2) {
                    Text(highlighted(result.title, query: query))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let detail = result.detail(locale: locale) {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if case .file = result {
                    EmptyView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 11)
            if !last { Divider().padding(.leading, 42) }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Cerca") {
    SearchView().previewEnvironment()
}

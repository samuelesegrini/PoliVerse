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
    @Environment(CourseService.self) private var courses
    @Environment(AgendaService.self) private var agenda
    @Environment(CareerService.self) private var career
    @Environment(RoomsService.self) private var rooms
    @Environment(NewsService.self) private var news
    @Environment(NoticeService.self) private var notices
    @Environment(WeBeepService.self) private var weBeep
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var scheme
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// The latest searches, newest first, one per line.
    @AppStorage("searchRecents") private var storedRecents = ""

    @State private var query = ""
    @State private var tokens: [Kind] = []
    @State private var expanded: Set<Kind> = []
    @State private var selectedEvent: AgendaEvent?
    @State private var selectedExam: ExamSession?
    @State private var spotlightCourse: Course?
    @State private var spotlightRoom: Classroom?
    @State private var spotlightTeacher: Teacher?

    /// A kind of result, which is also a token that narrows the search to it.
    nonisolated enum Kind: String, CaseIterable, Identifiable, Hashable {
        case courses, teachers, rooms, exams, calendar, materials, news, notices
        var id: String { rawValue }

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

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmed.isEmpty }

    private func shows(_ kind: Kind) -> Bool {
        tokens.isEmpty || tokens.contains(kind)
    }

    private var recents: [String] {
        storedRecents.split(separator: "\n").map(String.init)
    }

    private func remember(_ search: String) {
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard search.count >= 2 else { return }
        let kept = [search] + recents.filter { $0.caseInsensitiveCompare(search) != .orderedSame }
        storedRecents = kept.prefix(8).joined(separator: "\n")
    }

    // MARK: - Matching

    private var matchedCourses: [Course] {
        guard isSearching, shows(.courses) else { return [] }
        return SearchMatch.rank(courses.courses, query: trimmed) {
            [$0.name, $0.teacher, $0.code ?? "", $0.academicYear]
        }
    }

    private var matchedEvents: [AgendaEvent] {
        guard isSearching, shows(.calendar) else { return [] }
        let upcoming = agenda.events.filter { $0.end > .now }
        return Array(SearchMatch.rank(upcoming, query: trimmed) {
            [$0.title, $0.room ?? "", $0.roomAcronym ?? ""]
        }.prefix(10))
    }

    private var matchedExams: [ExamSession] {
        guard isSearching, shows(.exams) else { return [] }
        return SearchMatch.rank(career.sessions, query: trimmed) {
            [$0.courseName, $0.room ?? "", $0.teacher ?? ""]
        }
    }

    private var matchedRooms: [Classroom] {
        guard trimmed.count >= 2, shows(.rooms) else { return [] }
        return Array(SearchMatch.rank(rooms.rooms, query: trimmed) {
            [$0.id, $0.buildingName ?? "", $0.campusName ?? "", $0.address ?? ""]
        }.prefix(8))
    }

    private var matchedTeachers: [Teacher] {
        guard trimmed.count >= 2, shows(.teachers) else { return [] }
        let roster = Teacher.roster(courses: courses.courses, sessions: career.sessions)
        return Array(SearchMatch.rank(roster, query: trimmed) {
            [$0.name, $0.email ?? ""]
        }.prefix(8))
    }

    private var matchedNews: [NewsItem] {
        guard trimmed.count >= 2, shows(.news) else { return [] }
        return Array(SearchMatch.rank(news.items, query: trimmed) {
            [$0.title, $0.summary ?? "", $0.category ?? ""]
        }.prefix(6))
    }

    private var matchedNotices: [Notice] {
        guard trimmed.count >= 2, shows(.notices) else { return [] }
        return Array(SearchMatch.rank(notices.notices, query: trimmed) {
            [$0.title, $0.body ?? "", $0.category ?? ""]
        }.prefix(6))
    }

    private var matchedFiles: [WeBeepFile] {
        guard trimmed.count >= 2, shows(.materials) else { return [] }
        return Array(SearchMatch.rank(weBeep.sections.flatMap(\.files), query: trimmed) {
            [$0.name, $0.sectionName]
        }.prefix(8))
    }

    /// Every result as one shape, grouped by kind in the order they are shown.
    private var results: [(kind: Kind, items: [Result])] {
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

    init(embedded: Bool = false, places: [NewDestination]? = nil) {
        self.embedded = embedded
        self.places = places
    }

    var body: some View {
        RootStack(embedded: embedded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if isSearching {
                        resultsContent
                    } else {
                        browseContent
                    }
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
            .courseScreen()
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
            .task {
                await rooms.load()
                await courses.load()
                await agenda.load(around: .now)
                await career.load()
                // Cheap and already-windowed, so searching them costs nothing
                // at the keystroke.
                await news.load()
                await notices.load()
            }
        }
    }

    // MARK: - Before a search

    @ViewBuilder
    private var browseContent: some View {
        LookTitle("Cerca")


        kindChips

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

    /// A colour of the look's ramp for a place, stable for its symbol.
    private func colour(for symbol: String) -> Flavor.RGB {
        FlavorRamp(style: style, scheme: scheme).colour(at: Double(TodayDigest.colourIndex(for: symbol)) / 7)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsContent: some View {
        let results = results
        if results.isEmpty {
            ContentUnavailableView.search(text: trimmed)
                .padding(.top, 40)
                .accessibilityIdentifier("search-empty")
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
    case course(Course), teacher(Teacher), room(Classroom), exam(ExamSession)
    case event(AgendaEvent), file(WeBeepFile), news(NewsItem), notice(Notice)

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
private struct PlaceTile: View {
    let title: Text
    let detail: Text
    let symbol: String
    let colour: Flavor.RGB

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

/// The best match, lifted above the rest: its symbol on a glass tile, the
/// name large, and what it is.
private struct TopHitPanel: View {
    let result: Result
    let query: String
    let colour: Flavor.RGB

    @Environment(\.locale) private var locale
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

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
    let result: Result
    let query: String
    let colour: Flavor.RGB
    let last: Bool

    @Environment(\.locale) private var locale

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

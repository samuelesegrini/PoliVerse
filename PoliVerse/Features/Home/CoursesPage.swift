import SwiftUI

/// Corsi: the course that matters now at the top, then the rest of today, the
/// favourites, and the other courses.
///
/// The top is one course on a card of glass in its colour — the lesson under
/// way or next, else the next one this week, else the first favourite — with
/// its notices, materials, recordings and forum a tap away. ``Hero/tiles``
/// draws the pile of course tiles the settings pages open with instead.
///
/// Under it, the rest of today's lessons, the favourites as a grid of tiles,
/// and the other courses as rows. The list opens on the latest academic year,
/// since a course is one year's edition; the menu across from the title picks
/// another, or every year.
struct CoursesPage: View {
    /// Which picture the page opens with.
    enum Hero {
        /// One course on a card of its colour, the one on now or next, with
        /// its sections a tap away.
        case spotlight
        /// The pile of course tiles, as the settings pages open.
        case tiles
    }

    /// Which picture the page opens with.
    var hero: Hero = .spotlight
    /// The moment the page is drawn at, for previews; `nil` follows the clock.
    var fixedNow: Date?

    /// The shared ``CourseModel``, from the environment.
    @Environment(CourseModel.self) private var courses
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``StudyProgrammeModel``, from the environment.
    @Environment(StudyProgrammeModel.self) private var programmes
    /// The shared ``CareersModel``, from the environment.
    @Environment(CareersModel.self) private var careers
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// The shared ``UpdateFeed``, from the environment.
    @Environment(UpdateFeed.self) private var feed
    /// The shared ``RecordingsModel``, from the environment, for the recordings
    /// still to watch.
    @Environment(RecordingsModel.self) private var recordings
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// The reader's text size, which folds the favourites' grid into one column.
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The look in use, which supplies the page's material and typeface.
    @Environment(\.look) private var style

    /// The academic year the list is filtered to, or `nil` for every year.
    @State private var year: String?
    /// True once the student has picked a year, so a reload does not move them
    /// back to the latest.
    @State private var yearChosen = false
    /// Which provenance the list is filtered to.
    @State private var originFilter: CourseOrigins.Filter = .all
    /// The provenances the student has corrected by hand, by course id.
    @State private var overrides = EnrolmentOverrides.all()
    /// The study plans of the account's other enrolments, which a course can belong to.
    @State private var otherPlans: [EnrolmentOrigin.Plan] = []
    /// Whether the WeBeep login sheet is presented.
    @State private var showingLogin = false
    /// Whether the hidden-courses sheet is presented.
    @State private var showingHidden = false
    #if DEBUG
    /// Debug builds only: the course a launch argument asks to open.
    @State private var debugCourse: Course?
    /// Debug builds only: true once that course has been opened, so it opens once.
    @State private var openedDebugCourse = false
    #endif

    /// Where each course comes from, worked out from the plans, the career and the student's own corrections.
    private var origins: CourseOrigins {
        CourseOrigins(student: session.student, career: career, programmes: programmes, otherPlans: otherPlans,
                      overrides: overrides, weBeep: weBeep)
    }

    /// WeBeep is where the list comes from: without it the list is empty for
    /// a reason the student can fix.
    private var needsLogin: Bool {
        !session.useMockData && !weBeep.isAuthenticated
    }

    /// The moment the page is drawn at.
    private var now: Date { fixedNow ?? .now }

    /// The view's content.
    var body: some View {
        let origins = origins
        let shown = origins.filter(courses.courses(in: year), by: originFilter)
        let favourites = shown.filter(\.isFavourite)
        let others = shown.filter { !$0.isFavourite }
        let lessons = todaysLessons(in: shown)
        let focus = spotlight(shown: shown, lessons: lessons)
        // The spotlight already shows the first lesson; what is left of the
        // day comes under it.
        // The day is Oggi's, and the lesson under way rides above the tabs:
        // Corsi answers what is new in the courses, so it lists no lessons.
        let later: [(course: Course, event: AgendaEvent)] = []

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                switch style.special {
                case .playful:
                    playfulHero(shown: shown)
                case .blueprint:
                    blueprintHero(shown: shown)
                case nil:
                    switch hero {
                    case .tiles:
                        tilesHero(shown: shown, lessons: lessons)
                    case .spotlight:
                        spotlightHero(shown: shown, focus: focus)
                    }
                }

                if needsLogin {
                    loginCard
                } else if courses.isLoading && courses.courses.isEmpty {
                    placeholder
                } else if courses.courses.isEmpty {
                    empty("Nessun corso", systemImage: "books.vertical",
                          detail: "Non risultano corsi attivi su WeBeep.")
                } else {
                    if !later.isEmpty {
                        block(hero == .spotlight ? "Più tardi oggi" : "A lezione oggi") {
                            VStack(spacing: 10) {
                                ForEach(Array(later.enumerated()), id: \.element.event.id) { index, lesson in
                                    NavigationLink(value: lesson.course) {
                                        if index == 0, hero == .tiles {
                                            LessonCard(course: lesson.course, lesson: lesson.event,
                                                       colour: colour(of: lesson.course), fixedNow: fixedNow)
                                        } else {
                                            LessonRow(course: lesson.course, lesson: lesson.event)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if style.special == .playful, !shown.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            PlayfulHeading("La tua libreria")
                            PlayfulShelf(courses: (favourites + others).map { ($0, colour(of: $0)) })
                        }
                    } else if style.special == .blueprint, !shown.isEmpty {
                        BlueprintCourseTable(courses: favourites + others)
                    } else {
                        if !favourites.isEmpty {
                            block("Preferiti") { grid(favourites) }
                        }
                        if !others.isEmpty {
                            block(favourites.isEmpty ? "I tuoi corsi" : "Altri corsi") { list(others, origins: origins) }
                        }
                    }
                    if shown.isEmpty {
                        empty("Nessun corso qui", systemImage: "line.3.horizontal.decrease",
                              detail: "Nessun corso corrisponde ai filtri scelti.")
                    }

                    if originFilter != .all {
                        Text("Dedotto confrontando i corsi con il piano di studi di ogni tua matricola. Tieni premuto un corso per correggerlo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .collapsingTitle("Corsi")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        // The course's own page, with its lessons, sittings, and every part
        // of it — notices, materials, forum, programme — one tap away.
        .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
        #if DEBUG
        // `-OpenCourse 2` opens the third course at launch, for trying it out.
        .navigationDestination(item: $debugCourse) { CourseDetailView(course: $0) }
        .onChange(of: courses.courses.isEmpty, initial: true) { _, empty in
            guard !empty, let index = UserDefaults.standard.string(forKey: "OpenCourse").flatMap(Int.init),
                  !openedDebugCourse, courses.visibleCourses.indices.contains(index) else { return }
            openedDebugCourse = true
            debugCourse = courses.visibleCourses[index]
        }
        #endif
        // The latest year until the student picks one; every year when there
        // is only one, so the menu has nothing to hide.
        .onChange(of: courses.academicYears, initial: true) { _, years in
            guard !yearChosen else { return }
            year = years.count > 1 ? years.first : nil
        }
        .task {
            await CourseOrigins.load(courses: courses, careers: careers, career: career, programmes: programmes,
                                     weBeep: weBeep, student: session.student) { otherPlans = $0 }
        }
        .refreshable { await courses.load(force: true) }
        .sheet(isPresented: $showingLogin) {
            // Forced: connecting WeBeep is exactly the moment the held
            // course list stopped being right.
            WeBeepLoginSheet { await courses.load(force: true) }
        }
        .sheet(isPresented: $showingHidden) { HiddenCoursesSheet() }
        .animation(.snappy, value: shown.map(\.id))
        .animation(.snappy, value: originFilter)
    }

    // MARK: - Hero

    /// The pile of course tiles, the page's name, one line on where things
    /// stand, and the year and provenance the list is showing.
    private func tilesHero(shown: [Course], lessons: [(course: Course, event: AgendaEvent)]) -> some View {
        let ramp = FlavorRamp(style: style, scheme: scheme)
        let unread = shown.reduce(0) { $0 + news(for: $1).total }
        return VStack(spacing: 18) {
            HeroTileStack(
                tiles: heroCourses(shown, lessons: lessons).map { course in
                    HeroTile(id: course.id, symbol: SubjectSymbol.symbol(for: course.name), colour: colour(of: course))
                },
                placeholder: HeroTile(id: "empty", symbol: "books.vertical", colour: ramp.neutral),
                showsPlaceholder: !courses.isLoading || !courses.courses.isEmpty,
                badge: unread > 0 ? HeroBadge(symbol: "bell.fill", tint: style.accent(scheme)) : nil,
                mode: ramp.mode)
                .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text("Corsi")
                    .font(style.dateFont.font(size: 40 * style.dateSize, weight: style.dateWeight))
                    .foregroundStyle(style.dateTint(scheme))
                    .accessibilityAddTraits(.isHeader)
                if let summary = summary(courses: shown.count, unread: unread, lessons: lessons.count) {
                    summary
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            if courses.academicYears.count > 1 || originFilter != .all {
                HStack(spacing: 8) {
                    if courses.academicYears.count > 1 { yearMenu }
                    originChip
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
    }

    /// The provenance filter from the menu, shown where the list is, with the
    /// way to take it off.
    @ViewBuilder
    private var originChip: some View {
        if originFilter != .all {
            LookChip(title: Text(originFilter.title), isOn: true, systemImage: "xmark") {
                originFilter = .all
            }
            .accessibilityHint("Togli il filtro")
        }
    }

    /// The title on the leading edge with the year menu across from it, then
    /// the course in the spotlight.
    private func spotlightHero(shown: [Course], focus: (course: Course, lesson: AgendaEvent?)?) -> some View {
        let unread = shown.reduce(0) { $0 + news(for: $1).total }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Corsi")
                        .font(style.dateFont.font(size: 38 * style.dateSize, weight: style.dateWeight))
                        .foregroundStyle(style.dateTint(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    if let summary = summary(courses: shown.count, unread: unread, lessons: 0) {
                        summary
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                Spacer(minLength: 8)
                if courses.academicYears.count > 1 { yearMenu }
            }
            .padding(.horizontal, 4)
            originChip
            if let focus {
                SpotlightCard(course: focus.course, lesson: focus.lesson, colour: colour(of: focus.course),
                              news: news(for: focus.course), toWatch: recordings.toWatch(in: focus.course),
                              fixedNow: fixedNow)
                    .id(focus.course.id)
                    .transition(.blurReplace)
            }
        }
        .padding(.top, 8)
        .animation(.snappy, value: focus?.course.id)
    }

    /// What is new in each course that has something new, most first.
    private func newsTallies(_ shown: [Course]) -> [CourseNewsTally] {
        shown
            .map { course in
                let badges = news(for: course)
                return CourseNewsTally(course: course, colour: colour(of: course),
                                       notices: badges.announcements, materials: badges.materials,
                                       exams: badges.exams, toWatch: recordings.toWatch(in: course))
            }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
    }

    /// Blueprint's top: the title with the year across from it, then table 1
    /// of what is new.
    private func blueprintHero(shown: [Course]) -> some View {
        let news = newsTallies(shown)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 12) {
                Text("Corsi")
                    .font(style.dateFont.font(size: 40 * style.dateSize, weight: style.dateWeight))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if courses.academicYears.count > 1 { yearMenu }
            }
            .padding(.horizontal, 4)
            originChip
            if !news.isEmpty {
                BlueprintNewsTable(news: Array(news.prefix(6)))
            }
        }
        .padding(.top, 8)
    }

    /// Giocherelloso's top: the title with the year across from it, then a
    /// card for each course with something new, most first.
    private func playfulHero(shown: [Course]) -> some View {
        let news = newsTallies(shown)
        let total = news.reduce(0) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Corsi")
                        .font(style.dateFont.font(size: 40 * style.dateSize, weight: style.dateWeight))
                        .foregroundStyle(style.dateTint(scheme))
                        .accessibilityAddTraits(.isHeader)
                    if !courses.courses.isEmpty {
                        Text(total > 0 ? String(localized: "\(total) novità in \(news.count) corsi")
                                       : String(localized: "Niente di nuovo nei tuoi corsi"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if courses.academicYears.count > 1 { yearMenu }
            }
            .padding(.horizontal, 4)
            originChip
            if !news.isEmpty {
                PlayfulNewsRail(news: Array(news.prefix(6)))
            }
        }
        .padding(.top, 8)
    }

    /// The course the spotlight is on: the one with the most that is new,
    /// else the first favourite. Chosen by news rather than by the clock —
    /// what is on now is Oggi's, and the lesson bar's above the tabs.
    private func spotlight(shown: [Course], lessons: [(course: Course, event: AgendaEvent)])
        -> (course: Course, lesson: AgendaEvent?)? {
        let busiest = shown
            .map { ($0, news(for: $0).total + recordings.toWatch(in: $0)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
        guard let course = busiest ?? shown.first(where: \.isFavourite) ?? shown.first else { return nil }
        return (course, nil)
    }

    /// Up to five courses for the picture: the one of the lesson under way or
    /// next today in front, then the favourites, then those with the most news.
    private func heroCourses(_ shown: [Course], lessons: [(course: Course, event: AgendaEvent)]) -> [Course] {
        let byNews = shown.sorted { news(for: $0).total > news(for: $1).total }
        var seen: Set<String> = []
        return (lessons.map(\.course) + shown.filter(\.isFavourite) + byNews)
            .filter { seen.insert($0.id).inserted }
            .prefix(5)
            .map { $0 }
    }

    /// "7 corsi · 8 novità · 2 lezioni oggi", leaving out what is nothing.
    private func summary(courses count: Int, unread: Int, lessons: Int) -> Text? {
        guard !courses.courses.isEmpty else { return nil }
        var parts = [String(localized: "\(count) corsi")]
        if unread > 0 { parts.append(String(localized: "\(unread) novità")) }
        if lessons == 1 { parts.append(String(localized: "1 lezione oggi")) }
        else if lessons > 1 { parts.append(String(localized: "\(lessons) lezioni oggi")) }
        return Text(verbatim: parts.joined(separator: " · "))
    }

    /// The academic year the list shows, as a menu of every year the courses
    /// come from and "Tutti gli anni".
    private var yearMenu: some View {
        Menu {
            Picker("Anno accademico", selection: Binding(
                get: { year },
                set: { year = $0; yearChosen = true })) {
                ForEach(courses.academicYears, id: \.self) { item in
                    Text(verbatim: item).tag(Optional(item))
                }
                Text("Tutti gli anni").tag(String?.none)
            }
        } label: {
            HStack(spacing: 6) {
                if let year { Text(verbatim: year).monospacedDigit() } else { Text("Tutti gli anni") }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Anno accademico")
        .accessibilityValue(year.map { Text(verbatim: $0) } ?? Text("Tutti gli anni"))
    }

    /// The toolbar menu: the provenance filter, and a way into the hidden courses.
    private var menu: some View {
        Menu {
            Picker("Mostra", selection: $originFilter) {
                ForEach(CourseOrigins.Filter.allCases, id: \.self) { filter in
                    if filter != .otherCareer || careers.hasChoice {
                        Text(filter.title).tag(filter)
                    }
                }
            }
            if !courses.hiddenOnly.isEmpty {
                Divider()
                Button("Corsi nascosti (\(courses.hiddenOnly.count))", systemImage: "eye.slash") {
                    showingHidden = true
                }
            }
        } label: {
            Label("Filtra", systemImage: originFilter == .all
                  ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("courses-filter")
    }

    // MARK: - Blocks

    /// A course's colour, as its own page draws it.
    private func colour(of course: Course) -> Flavor.RGB {
        CourseRamp(course: course, style: style, scheme: scheme).main
    }

    /// What is unread in a course, counted by kind.
    private func news(for course: Course) -> CourseHubBadges {
        CourseHubBadges(items: FeedItem.items(from: feed.recent, for: course), seenAt: feed.seenAt)
    }

    /// A heading and what belongs under it, spaced as Oggi's sections are.
    ///
    /// - Parameters:
    ///   - title: The heading.
    ///   - content: What goes under it.
    /// - Returns: The section.
    private func block<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading(title)
            content()
        }
    }

    /// The favourites as tiles, two to a row, or one at the largest text sizes.
    private func grid(_ list: [Course]) -> some View {
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(list) { course in
                NavigationLink(value: course) {
                    FavouriteTile(course: course, detail: nextLecture(of: course).map { lessonText($0, now: now, locale: locale) },
                                  unread: news(for: course).total)
                }
                .buttonStyle(.plain)
                .contextMenu { menuItems(course) }
            }
        }
    }

    /// A group of courses as rows on one card.
    ///
    /// - Parameters:
    ///   - list: The courses, in the order they are drawn.
    ///   - origins: Where each comes from.
    /// - Returns: The card.
    private func list(_ list: [Course], origins: CourseOrigins) -> some View {
        let padding: CGFloat = style.material.hasCard ? 14 : 0
        return VStack(spacing: 0) {
            ForEach(list) { course in
                NavigationLink(value: course) {
                    CourseRow(course: course, origin: origins.origin(of: course), now: now,
                              nextLecture: nextLecture(of: course),
                              news: news(for: course),
                              last: course.id == list.last?.id)
                }
                .buttonStyle(.plain)
                .contextMenu { menuItems(course) }
            }
        }
        .padding(.horizontal, padding)
        .padding(.vertical, padding / 2)
        .lookCard()
    }

    /// A course's context menu: favourite, hide, and its provenance.
    ///
    /// - Parameter course: The course the menu belongs to.
    /// - Returns: The menu's items.
    @ViewBuilder
    private func menuItems(_ course: Course) -> some View {
        Button(course.isFavourite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti",
               systemImage: course.isFavourite ? "star.slash" : "star") {
            courses.toggleFavourite(course)
        }
        // Mirrors WeBeep's own "Rimuovi dalla vista": the course stays
        // enrolled, it just stops crowding the list.
        Button("Nascondi", systemImage: "eye.slash") { courses.toggleHidden(course) }
        Divider()
        // A guess from the study plans: the student can always correct it.
        Section("Provenienza") {
            Button("Del mio piano di studi", systemImage: "checkmark.seal") { setOverride(.plan, course) }
            Button("Iscrizione libera", systemImage: "hand.raised") { setOverride(.byChoice, course) }
            if overrides[course.id] != nil {
                Button("Deduci automaticamente", systemImage: "wand.and.stars") { setOverride(nil, course) }
            }
        }
    }

    /// Records the student's own answer about where a course comes from.
    ///
    /// - Parameters:
    ///   - value: The provenance, or `nil` to go back to the deduced one.
    ///   - course: The course.
    private func setOverride(_ value: EnrolmentOrigin.Override?, _ course: Course) {
        EnrolmentOverrides.set(value, for: course.id)
        overrides = EnrolmentOverrides.all()
    }

    /// The card shown in place of the list when WeBeep has not been connected, which is where the list comes from.
    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Collega WeBeep", systemImage: "books.vertical")
                .font(.headline)
            Text("WeBeep usa un accesso separato da quello dei servizi d'ateneo. Serve una sola volta.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Accedi a WeBeep") { showingLogin = true }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .lookCard()
    }

    /// An empty state on the look's card.
    ///
    /// - Parameters:
    ///   - title: What is missing.
    ///   - systemImage: Its SF Symbol.
    ///   - detail: Why, or what to do about it.
    /// - Returns: The card.
    private func empty(_ title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .lookCard()
    }

    /// Four sample rows, redacted, standing in for the list while it loads.
    private var placeholder: some View {
        VStack(spacing: 0) {
            ForEach(Course.samples.prefix(4)) { course in
                CourseRow(course: course, origin: .unknown, nextLecture: nil,
                          news: CourseHubBadges(items: [], seenAt: nil), last: false)
            }
        }
        .padding(.horizontal, 14)
        .redacted(reason: .placeholder)
        .lookCard()
    }

    // MARK: - Lessons

    /// Matched by name, as the course page does: the agenda carries no code.
    private func matches(_ event: AgendaEvent, _ course: Course) -> Bool {
        let title = event.title.lowercased(), target = course.name.lowercased()
        return title.contains(target) || target.contains(title)
    }

    /// The course's next lesson still to finish.
    ///
    /// - Parameter course: The course.
    /// - Returns: The earliest such lesson, or `nil` when there is none.
    private func nextLecture(of course: Course) -> AgendaEvent? {
        agenda.events.lazy
            .filter { $0.kind == .lecture && $0.end > now && matches($0, course) }
            .min { $0.start < $1.start }
    }

    /// Today's lessons still to finish, each with the course it belongs to.
    private func todaysLessons(in list: [Course]) -> [(course: Course, event: AgendaEvent)] {
        todaysTimetable(in: list).filter { $0.event.end > now }
    }

    /// Every lesson today, finished ones too, each with the course it belongs to.
    private func todaysTimetable(in list: [Course]) -> [(course: Course, event: AgendaEvent)] {
        TodayDigest.timetable(events: agenda.events, day: now)
            .filter { $0.kind == .lecture }
            .compactMap { event in list.first { matches(event, $0) }.map { ($0, event) } }
    }
}

// MARK: - Rows

extension CourseHubBadges {
    /// Everything unread in the course, added up.
    fileprivate var total: Int { announcements + materials + exams }
}

/// When a lesson is, in the shortest form that is still unambiguous.
///
/// - Parameters:
///   - lecture: The lesson.
///   - now: The moment it is measured from.
///   - locale: The locale times are written in.
/// - Returns: "In corso", "Oggi alle …", "Domani alle …", or the weekday and time.
private func lessonText(_ lecture: AgendaEvent, now: Date = .now, locale: Locale) -> String {
    let time = lecture.start.formatted(.dateTime.hour().minute().locale(locale))
    if lecture.start <= now { return String(localized: "In corso") }
    let calendar = PoliMiDate.romeCalendar
    if calendar.isDate(lecture.start, inSameDayAs: now) { return String(localized: "Oggi alle \(time)") }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
       calendar.isDate(lecture.start, inSameDayAs: tomorrow) { return String(localized: "Domani alle \(time)") }
    return lecture.start.formatted(.dateTime.weekday(.wide).hour().minute().locale(locale)).capitalized
}

/// How many things are new in a course, as a capsule in the look's colour.
private struct UnreadBadge: View {
    /// How many.
    let count: Int

    /// The look in use, which supplies the badge's colour.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        Text(count, format: .number)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(style.palette(scheme).onAccent)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(style.accent(scheme), in: .capsule)
            .accessibilityLabel(Text("\(count) novità"))
    }
}

/// One course: its colour, its name, when it is next, and what is new.
private struct CourseRow: View {
    /// The course this row is about.
    let course: Course
    /// Where the course comes from, named in the row's second line.
    let origin: EnrolmentOrigin
    /// The moment the row is drawn at.
    var now: Date = .now
    /// The course's next lesson, when it has one.
    let nextLecture: AgendaEvent?
    /// What is unread in the course, counted by kind.
    let news: CourseHubBadges
    /// True for the last row on the card, which draws no divider.
    let last: Bool

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CourseIcon(course: course, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if news.total > 0 {
                    UnreadBadge(count: news.total)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            if !last {
                Divider().padding(.leading, 48)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// When the course is next, within the week; otherwise who and which year.
    private var detail: String? {
        var parts: [String] = []
        if let lecture = nextLecture, lecture.start < now.addingTimeInterval(7 * 86_400) {
            parts.append(lessonText(lecture, now: now, locale: locale))
            if let room = lecture.roomLabel { parts.append(room) }
        } else {
            if course.teacher != "—", !course.teacher.isEmpty { parts.append(course.teacher) }
            if course.academicYear != "—" { parts.append(course.academicYear) }
        }
        if let origin = CourseOrigins.label(origin) { parts.append(origin) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A favourite course as a tile of the grid: its icon, what is new, its
/// name, and when it is next.
private struct FavouriteTile: View {
    /// The course.
    let course: Course
    /// When it is next, if within reach.
    let detail: String?
    /// How much is unread in it.
    let unread: Int

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CourseIcon(course: course, size: 38)
                Spacer(minLength: 4)
                if unread > 0 { UnreadBadge(count: unread) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(detail ?? String(localized: "Nessuna lezione in vista"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .lookCard(cornerRadius: 22)
        .contentShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

/// Today's first lesson, on a card of glass tinted with its course's colour:
/// where it is, and how far through it is while it is on.
private struct LessonCard: View {
    /// The course the lesson belongs to.
    let course: Course
    /// The lesson itself.
    let lesson: AgendaEvent
    /// The course's colour, as its page draws it.
    let colour: Flavor.RGB
    /// The moment the card is drawn at, for previews; `nil` follows the clock.
    var fixedNow: Date?

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        // A minute is as fine as the bar can show, and the card turns from
        // "Alle 14:15" to "Adesso" on its own when the lesson starts.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = fixedNow ?? context.date
            let ongoing = lesson.isOngoing(at: now)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    CourseIcon(course: course, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(eyebrow(ongoing: ongoing))
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(colour.color)
                        Text(course.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if ongoing {
                    VStack(spacing: 6) {
                        ProgressView(value: fraction(at: now))
                            .tint(colour.color)
                        HStack {
                            Text(time(lesson.start))
                            Spacer()
                            Text("finisce alle \(time(lesson.end))")
                        }
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(time(lesson.start)) – \(time(lesson.end))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .glassEffect(.regular.tint(colour.color.opacity(0.22)).interactive(), in: .rect(cornerRadius: 26))
            .contentShape(.rect(cornerRadius: 26))
        }
        .accessibilityElement(children: .combine)
    }

    /// "Adesso · B.2.1", or "Alle 14:15 · B.2.1" before it starts.
    private func eyebrow(ongoing: Bool) -> String {
        let when = ongoing ? String(localized: "Adesso") : String(localized: "Alle \(time(lesson.start))")
        return [when, lesson.roomLabel].compactMap { $0 }.joined(separator: " · ")
    }

    /// How far through the lesson `now` is, from 0 to 1.
    private func fraction(at now: Date) -> Double {
        let length = lesson.end.timeIntervalSince(lesson.start)
        guard length > 0 else { return 0 }
        return min(max(now.timeIntervalSince(lesson.start) / length, 0), 1)
    }

    /// A time of day, as the locale writes it.
    private func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }
}

/// One course on a card of glass tinted with its colour: when it is next and
/// where, and its four sections a tap away.
///
/// The course's subject symbol is drawn oversized behind the text, cut by the
/// card's corner, so the card says which course before a word is read. The top
/// opens the course's page; the round shortcuts open its notices, materials,
/// recordings and forum directly, each with what is new there.
private struct SpotlightCard: View {
    /// The course in the spotlight.
    let course: Course
    /// Its lesson under way or next, or `nil` when it has none this week.
    let lesson: AgendaEvent?
    /// The course's colour, as its page draws it.
    let colour: Flavor.RGB
    /// What is unread in the course, counted by kind.
    let news: CourseHubBadges
    /// The course's recordings still to watch.
    let toWatch: Int
    /// The moment the card is drawn at, for previews; `nil` follows the clock.
    var fixedNow: Date?

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// The symbol behind the text, scaled with the reader's text.
    @ScaledMetric(relativeTo: .largeTitle) private var mark: CGFloat = 150

    /// The card's corner radius.
    private let radius: CGFloat = 30

    /// The view's content.
    var body: some View {
        // Each minute: the card turns from "Il prossimo" to "Adesso" when the
        // lesson starts, and its bar moves while it is on.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = fixedNow ?? context.date
            let ongoing = lesson?.isOngoing(at: now) == true
            VStack(alignment: .leading, spacing: 20) {
                NavigationLink(value: course) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(eyebrow(now: now, ongoing: ongoing))
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(colour.color)
                        Text(course.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.trailing, 48)
                        if let detail = detail(ongoing: ongoing) {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if ongoing, let lesson {
                            ProgressView(value: fraction(of: lesson, at: now))
                                .tint(colour.color)
                                .padding(.top, 8)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Apre il corso")

                HStack(alignment: .top, spacing: 4) {
                    shortcut("Avvisi", symbol: "megaphone", count: news.announcements,
                             value: newCount(news.announcements)) {
                        CourseForumsView(course: course, kind: .announcements)
                    }
                    shortcut("Materiali", symbol: "folder", count: news.materials,
                             value: newCount(news.materials)) {
                        CourseMaterialsView(course: course)
                    }
                    shortcut("Lezioni", symbol: "play.rectangle", count: toWatch,
                             value: toWatch > 0 ? Text("\(toWatch) da vedere") : nil) {
                        CourseRecordingsView(course: course)
                    }
                    shortcut("Forum", symbol: "bubble.left.and.bubble.right", count: 0, value: nil) {
                        CourseForumsView(course: course, kind: .discussion)
                    }
                }
            }
            .padding(20)
            .background(alignment: .topTrailing) {
                Image(systemName: SubjectSymbol.symbol(for: course.name))
                    .font(.system(size: mark, weight: .ultraLight))
                    .foregroundStyle(colour.color.opacity(0.14))
                    .offset(x: mark * 0.18, y: -mark * 0.16)
                    .accessibilityHidden(true)
            }
            .clipShape(.rect(cornerRadius: radius))
            .glassEffect(.regular.tint(colour.color.opacity(0.2)), in: .rect(cornerRadius: radius))
        }
    }

    /// "Adesso · B.2.1", "Il prossimo · oggi alle 10:15", or "Tra i preferiti"
    /// when the course has no lesson this week.
    private func eyebrow(now: Date, ongoing: Bool) -> String {
        guard let lesson else { return String(localized: "Tra i preferiti") }
        if ongoing {
            return [String(localized: "Adesso"), lesson.roomLabel].compactMap { $0 }.joined(separator: " · ")
        }
        let when = lessonText(lesson, now: now, locale: locale).lowercased(with: locale)
        return String(localized: "Il prossimo · \(when)")
    }

    /// "B.2.1 · fino alle 12:15", or "B.2.1 · 14:15–16:15" before it starts; who
    /// teaches it when there is no lesson.
    private func detail(ongoing: Bool) -> String? {
        guard let lesson else {
            return course.teacher != "—" && !course.teacher.isEmpty ? course.teacher : nil
        }
        let span = ongoing
            ? String(localized: "fino alle \(time(lesson.end))")
            : "\(time(lesson.start))–\(time(lesson.end))"
        return [ongoing ? nil : lesson.roomLabel, span].compactMap { $0 }.joined(separator: " · ")
    }

    /// One of the course's sections, as a round button with what is new on its corner.
    private func shortcut<Destination: View>(
        _ title: LocalizedStringKey, symbol: String, count: Int, value: Text?,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(colour.color)
                    .frame(width: 52, height: 52)
                    .background(Color(.systemBackground).opacity(0.72), in: .circle)
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            UnreadBadge(count: count)
                                .offset(x: 8, y: -4)
                        }
                    }
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(value ?? Text(verbatim: ""))
        .accessibilityAddTraits(.isButton)
    }

    /// "1 nuovo" or "3 nuovi", as the course page says it, or `nil` for none.
    private func newCount(_ count: Int) -> Text? {
        guard count > 0 else { return nil }
        return Text(count == 1 ? "1 nuovo" : "\(count) nuovi")
    }

    /// How far through the lesson `now` is, from 0 to 1.
    private func fraction(of lesson: AgendaEvent, at now: Date) -> Double {
        let length = lesson.end.timeIntervalSince(lesson.start)
        guard length > 0 else { return 0 }
        return min(max(now.timeIntervalSince(lesson.start) / length, 0), 1)
    }

    /// A time of day, as the locale writes it.
    private func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }
}

/// A later lesson today, as a row on the look's card with its start time large.
private struct LessonRow: View {
    /// The course the lesson belongs to.
    let course: Course
    /// The lesson itself.
    let lesson: AgendaEvent

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        let end = lesson.end.formatted(.dateTime.hour().minute().locale(locale))
        HStack(spacing: 12) {
            CourseIcon(course: course, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text([lesson.roomLabel, String(localized: "fino alle \(end)")].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(lesson.start.formatted(.dateTime.hour().minute().locale(locale)))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .lookCard(cornerRadius: 22)
        .contentShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

/// A course's subject symbol on its colour: how a course is recognised across
/// Corsi and its own page, which opens on the same symbol in glass.
struct CourseIcon: View {
    /// The course whose symbol and colour are drawn.
    let course: Course
    /// The icon's side, in points.
    var size: CGFloat = 38

    /// The look in use, which the course's colour is checked against.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        GlassTile(symbol: SubjectSymbol.symbol(for: course.name),
                  colour: CourseRamp(course: course, style: style, scheme: scheme).main,
                  side: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Hidden courses

/// The courses removed from the list, with a way to bring each one back.
private struct HiddenCoursesSheet: View {
    /// The shared ``CourseModel``, from the environment.
    @Environment(CourseModel.self) private var courses
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss

    /// The view's content.
    var body: some View {
        NavigationStack {
            List(courses.hiddenOnly) { course in
                HStack(spacing: 12) {
                    CourseIcon(course: course, size: 30)
                    Text(course.name).font(.subheadline)
                    Spacer()
                    Button("Mostra") { courses.toggleHidden(course) }
                        .buttonStyle(.borderless)
                }
            }
            .navigationTitle("Corsi nascosti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") { dismiss() }
                }
            }
            .overlay {
                if courses.hiddenOnly.isEmpty {
                    ContentUnavailableView("Nessun corso nascosto", systemImage: "eye")
                }
            }
        }
    }
}

// MARK: - Previews

/// The page on the sample account, loaded and drawn at a chosen moment.
private struct CoursesPreview: View {
    /// Which picture the page opens with.
    var hero: CoursesPage.Hero
    /// The moment to draw at, or `nil` for the clock.
    var at: Date?

    /// The view's content.
    var body: some View {
        NavigationStack { CoursesPage(hero: hero, fixedNow: at) }
            .previewEnvironment()
            .task {
                await PreviewEnvironment.courses.load()
                await PreviewEnvironment.agenda.load(around: at ?? .now)
            }
    }

    /// A time on a day of the sample week, which runs Monday to Friday of the
    /// current one.
    ///
    /// - Parameters:
    ///   - day: Days from Monday.
    ///   - hour: The hour.
    ///   - minute: The minute.
    /// - Returns: The moment.
    static func moment(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let calendar = PoliMiDate.romeCalendar
        let week = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let date = calendar.date(byAdding: .day, value: day, to: week) ?? week
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }
}

#Preview("In evidenza · adesso") {
    CoursesPreview(hero: .spotlight)
}

#Preview("In evidenza · durante una lezione") {
    CoursesPreview(hero: .spotlight, at: CoursesPreview.moment(day: 2, 9, 30))
}

#Preview("In evidenza · tra due lezioni") {
    CoursesPreview(hero: .spotlight, at: CoursesPreview.moment(day: 2, 12, 30))
}

#Preview("In evidenza · lezioni finite") {
    CoursesPreview(hero: .spotlight, at: CoursesPreview.moment(day: 2, 18))
}

#Preview("In evidenza · fine settimana") {
    CoursesPreview(hero: .spotlight, at: CoursesPreview.moment(day: 5, 10))
}

#Preview("In evidenza · scuro") {
    CoursesPreview(hero: .spotlight, at: CoursesPreview.moment(day: 2, 9, 30))
        .preferredColorScheme(.dark)
}

#Preview("In evidenza · testo grande") {
    CoursesPreview(hero: .spotlight, at: CoursesPreview.moment(day: 2, 9, 30))
        .dynamicTypeSize(.accessibility2)
}

#Preview("Pila · durante una lezione") {
    CoursesPreview(hero: .tiles, at: CoursesPreview.moment(day: 2, 9, 30))
}

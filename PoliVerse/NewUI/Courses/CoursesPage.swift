import SwiftUI

/// Corsi, drawn as Oggi is: the look's sheet behind, a title in the date's
/// typeface, and blocks with Oggi's headings on cards of the look's material.
///
/// Today's lessons come first, each in its course's colour as on Oggi, since
/// "which course am I going to" is the reason most visits start. Then the
/// favourites and the rest, one card each, with what is new beside a course.
struct CoursesPage: View {
    @Environment(CourseService.self) private var courses
    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep
    @Environment(CareerService.self) private var career
    @Environment(StudyProgrammeService.self) private var programmes
    @Environment(CareersService.self) private var careers
    @Environment(AgendaService.self) private var agenda
    @Environment(UpdateFeed.self) private var feed
    @Environment(\.locale) private var locale

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    @State private var year: String?
    @State private var originFilter: CourseOrigins.Filter = .all
    @State private var overrides = EnrolmentOverrides.all()
    @State private var otherPlans: [EnrolmentOrigin.Plan] = []
    @State private var showingLogin = false
    @State private var showingHidden = false
    /// The big title has scrolled under the bar, so the bar names the page.
    @State private var titleInBar = false

    private var origins: CourseOrigins {
        CourseOrigins(student: session.student, career: career, programmes: programmes, otherPlans: otherPlans,
                      overrides: overrides, weBeep: weBeep)
    }

    /// WeBeep is where the list comes from: without it the list is empty for
    /// a reason the student can fix.
    private var needsLogin: Bool {
        !session.useMockData && !weBeep.isAuthenticated
    }

    var body: some View {
        let origins = origins
        let shown = origins.filter(courses.courses(in: year), by: originFilter)
        let favourites = shown.filter(\.isFavourite)
        let others = shown.filter { !$0.isFavourite }

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LookTitle("Corsi", subtitle: subtitle(count: shown.count))

                if courses.academicYears.count > 1 || originFilter != .all {
                    filters
                }

                if needsLogin {
                    loginCard
                } else if courses.isLoading && courses.courses.isEmpty {
                    placeholder
                } else if courses.courses.isEmpty {
                    empty("Nessun corso", systemImage: "books.vertical",
                          detail: "Non risultano corsi attivi su WeBeep.")
                } else {
                    let lessons = todaysLessons(in: shown)
                    if !lessons.isEmpty {
                        block("A lezione oggi") {
                            VStack(spacing: 8) {
                                ForEach(lessons, id: \.event.id) { lesson in
                                    NavigationLink(value: lesson.course) {
                                        LessonCourseCard(course: lesson.course, lesson: lesson.event)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !favourites.isEmpty {
                        block("Preferiti") { list(favourites, origins: origins) }
                    }
                    if !others.isEmpty {
                        block(favourites.isEmpty ? "I tuoi corsi" : "Altri corsi") { list(others, origins: origins) }
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
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 70
        } action: { _, past in
            withAnimation(.snappy(duration: 0.2)) { titleInBar = past }
        }
        .lookPage()
        .navigationTitle("Corsi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The page's own title says "Corsi" until it scrolls away.
            ToolbarItem(placement: .principal) {
                Text("Corsi")
                    .font(.headline)
                    .opacity(titleInBar ? 1 : 0)
                    .accessibilityHidden(!titleInBar)
            }
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .navigationDestination(for: Course.self) { CourseMaterialsView(course: $0) }
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

    private func subtitle(count: Int) -> Text? {
        guard !courses.courses.isEmpty else { return nil }
        let courseCount = Text("\(count) corsi")
        if let year { return Text("\(courseCount) · \(year)") }
        return courseCount
    }

    // MARK: - Filters

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if originFilter != .all {
                    // The filter from the menu, shown where the list is, with
                    // the way to take it off.
                    LookChip(title: Text(originFilter.title), isOn: true, systemImage: "xmark") {
                        originFilter = .all
                    }
                    .accessibilityHint("Togli il filtro")
                }
                if courses.academicYears.count > 1 {
                    LookChip(title: Text("Tutti gli anni"), isOn: year == nil) { year = nil }
                    ForEach(courses.academicYears, id: \.self) { item in
                        // The active year again clears it, so the filter is
                        // never a one-way door.
                        LookChip(title: Text(verbatim: item), isOn: year == item) {
                            year = year == item ? nil : item
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }

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

    private func block<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading(title)
            content()
        }
    }

    private func list(_ list: [Course], origins: CourseOrigins) -> some View {
        let padding: CGFloat = style.material.hasCard ? 14 : 0
        return VStack(spacing: 0) {
            ForEach(list) { course in
                NavigationLink(value: course) {
                    CourseRow(course: course, origin: origins.origin(of: course),
                              nextLecture: nextLecture(of: course),
                              news: CourseHubBadges(items: FeedItem.items(from: feed.recent, for: course),
                                                    seenAt: feed.seenAt),
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

    private func setOverride(_ value: EnrolmentOrigin.Override?, _ course: Course) {
        EnrolmentOverrides.set(value, for: course.id)
        overrides = EnrolmentOverrides.all()
    }

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

    private func empty(_ title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .lookCard()
    }

    private var placeholder: some View {
        VStack(spacing: 0) {
            ForEach(MockData.courses.prefix(4)) { course in
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

    private func nextLecture(of course: Course) -> AgendaEvent? {
        agenda.events.lazy
            .filter { $0.kind == .lecture && $0.end > .now && matches($0, course) }
            .min { $0.start < $1.start }
    }

    /// Today's lessons still to finish, each with the course it belongs to.
    private func todaysLessons(in list: [Course]) -> [(course: Course, event: AgendaEvent)] {
        TodayDigest.timetable(events: agenda.events, day: .now)
            .filter { $0.kind == .lecture && $0.end > .now }
            .compactMap { event in list.first { matches(event, $0) }.map { ($0, event) } }
    }
}

// MARK: - Rows

/// One course: its colour, its name, when it is next, and what is new.
private struct CourseRow: View {
    let course: Course
    let origin: EnrolmentOrigin
    let nextLecture: AgendaEvent?
    let news: CourseHubBadges
    let last: Bool

    @Environment(\.locale) private var locale
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme

    private var unread: Int { news.announcements + news.materials + news.exams }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CourseMonogram(course: course, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.subheadline.weight(.medium))
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
                if unread > 0 {
                    Text(unread, format: .number)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(style.palette(scheme).onAccent)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(style.accent(scheme), in: .capsule)
                        .accessibilityLabel(Text("\(unread) novità"))
                }
                if course.isFavourite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Preferito")
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 11)
            if !last {
                Divider().padding(.leading, 50)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// When the course is next, within the week; otherwise who and which year.
    private var detail: String? {
        var parts: [String] = []
        if let lecture = nextLecture, lecture.start < .now.addingTimeInterval(7 * 86_400) {
            parts.append(lectureText(lecture))
            if let room = lecture.roomAcronym ?? lecture.room { parts.append(room) }
        } else {
            if course.teacher != "—", !course.teacher.isEmpty { parts.append(course.teacher) }
            if course.academicYear != "—" { parts.append(course.academicYear) }
        }
        if let origin = CourseOrigins.label(origin) { parts.append(origin) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func lectureText(_ lecture: AgendaEvent) -> String {
        let time = lecture.start.formatted(.dateTime.hour().minute().locale(locale))
        if lecture.start <= .now { return String(localized: "In corso") }
        let calendar = PoliMiDate.romeCalendar
        if calendar.isDateInToday(lecture.start) { return String(localized: "Oggi alle \(time)") }
        if calendar.isDateInTomorrow(lecture.start) { return String(localized: "Domani alle \(time)") }
        return lecture.start.formatted(.dateTime.weekday(.wide).hour().minute().locale(locale)).capitalized
    }
}

/// A lesson today, as a card in its course's colour with Oggi's sheen.
private struct LessonCourseCard: View {
    let course: Course
    let lesson: AgendaEvent

    @Environment(\.locale) private var locale

    var body: some View {
        let colour = Theme.accent(for: course)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text([lesson.room ?? lesson.roomAcronym].compactMap { $0 }.joined())
                    .font(.caption)
                    .opacity(0.8)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                if lesson.isOngoing() {
                    Text("Adesso")
                        .font(.caption.weight(.bold))
                } else {
                    Text(lesson.start.formatted(.dateTime.hour().minute().locale(locale)))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                Text("fino alle \(lesson.end.formatted(.dateTime.hour().minute().locale(locale)))")
                    .font(.caption2)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background {
            shape.fill(colour)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.glossSheen(.float2(proxy.size), .float(0.5)))
                }
        }
        .shadow(color: colour.opacity(0.3), radius: 8, y: 4)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

/// A course's initials on its colour: how a course is recognised across
/// Corsi and its own page.
struct CourseMonogram: View {
    let course: Course
    var size: CGFloat = 38

    var body: some View {
        Text(course.monogram)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.onAccent)
            .frame(width: size, height: size)
            .background(Theme.accent(for: course).gradient, in: .rect(cornerRadius: size * 0.2237, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension Course {
    /// "AC" for "Architetture dei Calcolatori": skips the short joining words.
    var monogram: String {
        let skip: Set<String> = ["di", "dei", "del", "della", "delle", "e", "ed", "per", "a", "and", "of", "the", "in"]
        return String(name
            .split(whereSeparator: { !$0.isLetter })
            .filter { !skip.contains($0.lowercased()) }
            .prefix(2)
            .compactMap(\.first)).uppercased()
    }
}

// MARK: - Hidden courses

private struct HiddenCoursesSheet: View {
    @Environment(CourseService.self) private var courses
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(courses.hiddenOnly) { course in
                HStack(spacing: 12) {
                    CourseMonogram(course: course, size: 30)
                    Text(course.name).font(.subheadline)
                    Spacer()
                    Button("Mostra") { courses.toggleHidden(course) }
                        .buttonStyle(.borderless)
                }
            }
            .lookPage()
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

#Preview("Corsi") {
    NavigationStack { CoursesPage() }.previewEnvironment()
}

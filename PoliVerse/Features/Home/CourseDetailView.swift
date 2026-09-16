import SwiftUI

/// Everything about one course, drawn as Oggi is: the look's sheet behind,
/// Oggi's headings, rows on cards of the look's material, and the course's own
/// colour for what belongs to it.
///
/// In order of what a student opens a course for: when the next lessons are,
/// the next sitting and the ones around it, the parts of the course — notices,
/// materials, forum, programme, information — how the exam works, and what
/// changed. Where they stand with it — passed, or not yet — sits under the
/// name, before any of that.
struct CourseDetailView: View {
    let course: Course

    @Environment(AgendaService.self) private var agenda
    @Environment(CareerService.self) private var career
    @Environment(CourseService.self) private var courses
    @Environment(\.locale) private var locale
    @Environment(UpdateFeed.self) private var feed
    @Environment(ManifestiService.self) private var manifesti
    @Environment(StudyProgrammeService.self) private var programmes
    @Environment(Session.self) private var session
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme

    private var ramp: CourseRamp { CourseRamp(course: course, style: style, scheme: scheme) }

    @State private var selectedExam: ExamSession?
    @State private var bracketTeacher: String?
    @State private var syllabus: Syllabus?

    private var accent: Color { Theme.accent(for: course) }

    /// Agenda entries whose title matches this course.
    ///
    /// The agenda and the teachings endpoint do not share an identifier — the
    /// agenda carries a display title, not `c_insegn_piano` — so matching is by
    /// normalised name. Imperfect, but the alternative is showing nothing.
    private var lectures: [AgendaEvent] {
        let target = course.name.lowercased()
        return agenda.events
            .filter { $0.end > .now }
            .filter { event in
                let title = event.title.lowercased()
                return title.contains(target) || target.contains(title)
            }
            .sorted { $0.start < $1.start }
            .prefix(4)
            .map { $0 }
    }

    private var examSessions: [ExamSession] {
        career.sessions
            .filter { $0.isOf(courseCode: course.id, courseName: course.name) }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// The teaching's libretto row, for its mark once passed.
    private var librettoEntry: LibrettoExam? {
        career.libretto.first { $0.id == course.id || $0.id == course.teachingCode
            || $0.name.caseInsensitiveCompare(course.name) == .orderedSame }
    }

    var body: some View {
        let sittings = examSessions
        let upcoming = sittings.filter { $0.grade == nil && ($0.date ?? .distantPast) > .now }
        let past = sittings.filter { $0.grade != nil }.reversed().map { $0 }
        let news = FeedItem.items(from: feed.recent, for: course)
        let lectures = lectures

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero

                glance(lectures: lectures, next: upcoming.first, news: news)

                if !lectures.isEmpty {
                    block("Lezioni") {
                        rows(lectures) { lecture, last in lectureRow(lecture, last: last) }
                    }
                }

                if !sittings.isEmpty {
                    block("Appelli") {
                        VStack(spacing: 10) {
                            if let next = upcoming.first {
                                Button { selectedExam = next } label: { NextSittingCard(exam: next, accent: accent) }
                                    .buttonStyle(.plain)
                            }
                            let others = Array(upcoming.dropFirst()) + past
                            if !others.isEmpty {
                                rows(others) { sitting, last in
                                    Button { selectedExam = sitting } label: { sittingRow(sitting, last: last) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                block("Corso") { parts }

                if let syllabus, !syllabus.isEmpty {
                    block("In breve") { overview(syllabus) }
                }

                if !news.isEmpty {
                    block("Novità") {
                        VStack(spacing: 0) {
                            ForEach(news.prefix(3)) { item in
                                ExamUpdateRow(item: item, isUnread: item.isUnread(since: feed.seenAt), card: false)
                                if item.id != news.prefix(3).last?.id { Divider().padding(.leading, 52) }
                            }
                            if news.count > 3 {
                                Divider()
                                NavigationLink { ExamUpdatesView() } label: {
                                    row(symbol: "bell.badge", title: String(localized: "Tutte le novità esami"),
                                        last: true, chevron: true)
                                        .padding(.horizontal, 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .lookCard()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .lookPage()
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    courses.toggleFavourite(course)
                } label: {
                    Image(systemName: course.isFavourite ? "star.fill" : "star")
                        .foregroundStyle(course.isFavourite ? .yellow : accent)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(course.isFavourite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti")
            }
        }
        .sheet(item: $selectedExam) { ExamDetailView(exam: $0) }
        .task {
            async let lectures: Void = agenda.load(around: .now)
            await career.load()
            // The scheda takes a few pages to find: start now, so "Programma"
            // opens on an answer rather than a spinner. After the career, so
            // the degree course is known and the tap asks the same question.
            if !session.useMockData,
               let pick = await programmes.pick(teachingCode: course.teachingCode, name: course.name,
                                                yearCode: course.academicYearStart, courseID: course.id) {
                // Only from the student's own plan: the catalogue-wide fallback
                // may be another degree course, with other lecturers.
                let names = pick.teachers
                if pick.matchesDegree, !names.isEmpty { bracketTeacher = names.joined(separator: ", ") }
                if let id = pick.module.syllabusID { syllabus = await manifesti.syllabus(for: id) }
            }
            await lectures
        }
    }

    // MARK: - Hero

    /// The course's colour and name in the middle, who teaches it and its
    /// facts under, and where the student stands with it.
    private var hero: some View {
        VStack(spacing: 10) {
            CourseMonogram(course: course, size: 76)
                .shadow(color: accent.opacity(0.35), radius: 14, y: 6)
                .padding(.bottom, 4)
            Text(course.name)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let facts {
                Text(facts)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            standing
                .padding(.top, 6)
            if let email = course.teacherEmail, let url = URL(string: "mailto:\(email)") {
                Link(destination: url) {
                    Label("Scrivi al docente", systemImage: "envelope")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .tint(accent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// "Stefano Ceri · 8 CFU · Semestre 2 · 2025/26": the lecturer of the
    /// student's bracket once the plan says who, since a WeBeep course alone
    /// carries no teacher.
    private var facts: String? {
        var parts: [String] = []
        let teacher = bracketTeacher ?? course.teacher
        if !teacher.isEmpty, teacher != "—" { parts.append(teacher) }
        if course.cfu > 0 { parts.append(String(localized: "\(course.cfu) CFU")) }
        if course.semester != "—" { parts.append(String(localized: "Semestre \(course.semester)")) }
        if course.academicYear != "—" { parts.append(course.academicYear) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Passed with its mark, or not yet: a capsule under the name rather than
    /// a card of its own, since the sittings say the rest.
    @ViewBuilder
    private var standing: some View {
        if let entry = librettoEntry {
            let passed = entry.isPassed
            HStack(spacing: 8) {
                Image(systemName: passed ? "checkmark.seal.fill" : "hourglass")
                    .foregroundStyle(passed ? .green : .secondary)
                if passed {
                    Text(entry.date.map { String(localized: "Superato il \($0.formatted(.dateTime.day().month(.wide).year().locale(locale)))") }
                         ?? String(localized: "Superato"))
                    if entry.displayGrade != "—" {
                        Text(entry.displayGrade)
                            .font(style.dateFont.font(size: 20, weight: style.dateWeight))
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("Esame non ancora sostenuto")
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .lookCard(cornerRadius: 19)
            .accessibilityElement(children: .combine)
        }
    }

    /// The next lesson, the next sitting and what is new, before the blocks
    /// that say each at length.
    @ViewBuilder
    private func glance(lectures: [AgendaEvent], next: ExamSession?, news: [FeedItem]) -> some View {
        let unread = news.filter { $0.isUnread(since: feed.seenAt) }.count
        var items: [GlanceStrip.Item] = []
        let _ = {
            if let lecture = lectures.first {
                items.append(.init(id: "lesson",
                                   value: lecture.start <= .now ? String(localized: "Ora")
                                       : lecture.start.formatted(.dateTime.hour().minute().locale(locale)),
                                   label: lecture.start <= .now ? String(localized: "a lezione") : dayLabel(lecture.start)))
            }
            if let date = next?.date {
                let calendar = PoliMiDate.romeCalendar
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now),
                                                   to: calendar.startOfDay(for: date)).day ?? 0
                items.append(.init(id: "exam", value: "\(days)",
                                   label: days == 1 ? String(localized: "giorno all'appello") : String(localized: "giorni all'appello")))
            }
            items.append(.init(id: "news", value: "\(unread)",
                               label: unread == 1 ? String(localized: "novità") : String(localized: "novità")))
        }()
        if items.count > 1 {
            GlanceStrip(items: items, tint: ramp.main.color)
        }
    }

    // MARK: - Parts

    /// The parts of the course, with what is new in each.
    private var parts: some View {
        let badges = CourseHubBadges(items: FeedItem.items(from: feed.recent, for: course), seenAt: feed.seenAt)
        return VStack(spacing: 0) {
            NavigationLink { CourseForumsView(course: course, kind: .announcements) } label: {
                row(symbol: "megaphone", title: String(localized: "Avvisi"), trailing: newCount(badges.announcements),
                    tile: ramp.colour(0, of: 5), last: false, chevron: true)
            }
            NavigationLink { CourseMaterialsView(course: course) } label: {
                row(symbol: "folder", title: String(localized: "Materiali"), trailing: newCount(badges.materials),
                    tile: ramp.colour(1, of: 5), last: false, chevron: true)
            }
            NavigationLink { CourseForumsView(course: course, kind: .discussion) } label: {
                row(symbol: "bubble.left.and.bubble.right", title: String(localized: "Forum"), tile: ramp.colour(2, of: 5), last: false, chevron: true)
            }
            NavigationLink { CourseSyllabusView(course: course) } label: {
                row(symbol: "book.closed", title: String(localized: "Programma"), tile: ramp.colour(3, of: 5), last: false, chevron: true)
            }
            NavigationLink { CourseInfoView(course: course) } label: {
                row(symbol: "info.circle", title: String(localized: "Informazioni"), tile: ramp.colour(4, of: 5), last: true, chevron: true)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, cardPadding)
        .padding(.vertical, cardPadding / 2)
        .lookCard()
    }

    private func newCount(_ count: Int) -> Text? {
        guard count > 0 else { return nil }
        return Text(count == 1 ? "1 nuovo" : "\(count) nuovi")
    }

    // MARK: - Lectures

    private func lectureRow(_ lecture: AgendaEvent, last: Bool) -> some View {
        let live = lecture.start <= .now
        let time = lecture.start.formatted(.dateTime.hour().minute().locale(locale))
        return row(symbol: live ? "dot.radiowaves.left.and.right" : "clock",
                   title: live ? String(localized: "In corso") : "\(dayLabel(lecture.start)) · \(time)",
                   detail: live ? String(localized: "fino alle \(lecture.end.formatted(.dateTime.hour().minute().locale(locale)))") : nil,
                   trailing: Text(lecture.roomAcronym ?? lecture.room ?? String(localized: "Aula da definire")),
                   tile: live ? Flavor.RGB(red: 0.2, green: 0.62, blue: 0.36) : nil,
                   last: last)
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = PoliMiDate.romeCalendar
        if calendar.isDateInToday(date) { return String(localized: "Oggi") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Domani") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale)).capitalized
    }

    // MARK: - Sittings

    private func sittingRow(_ sitting: ExamSession, last: Bool) -> some View {
        let tint = ExamDetailView.accent(for: sitting.status)
        let trailing: Text = if let grade = sitting.grade {
            Text(grade.display)
                .font(style.dateFont.font(size: 20, weight: style.dateWeight))
                .foregroundStyle(tint)
        } else {
            Text(sitting.status.label).foregroundStyle(tint)
        }
        return row(symbol: sitting.grade == nil ? "calendar" : "pencil.and.list.clipboard",
                   title: sitting.date?.formatted(.dateTime.day().month(.wide).year().locale(locale))
                       ?? String(localized: "Data da definire"),
                   detail: sitting.kind?.nonEmpty,
                   trailing: trailing, last: last, chevron: true)
    }

    // MARK: - Overview

    private func overview(_ syllabus: Syllabus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let facts: [(String, String)] = [
                syllabus.assistedMinutes.map { ("\($0 / 60)", String(localized: "ore in aula")) },
                syllabus.selfStudyMinutes.map { ("\($0 / 60)", String(localized: "ore di studio")) },
                syllabus.teachingType.map { ($0, String(localized: "tipo")) },
            ].compactMap { $0 }
            if !facts.isEmpty {
                HStack(spacing: 8) {
                    ForEach(facts, id: \.1) { value, label in
                        VStack(spacing: 2) {
                            Text(value)
                                .font(style.dateFont.font(size: 22, weight: style.dateWeight))
                                .foregroundStyle(accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(label).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .lookCard(cornerRadius: 18)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                let lines = overviewLines(syllabus)
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    row(symbol: line.symbol, title: line.text, tile: line.tile, last: false)
                }
                if let objectives = syllabus.objectives?.nonEmpty {
                    Text(objectives)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(.vertical, 12)
                    Divider()
                }
                NavigationLink { CourseSyllabusView(course: course) } label: {
                    row(symbol: "book.closed", title: String(localized: "Programma, libri e dettagli"),
                        last: true, chevron: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, cardPadding / 2)
            .lookCard()
        }
    }

    private struct OverviewLine {
        let symbol: String
        let text: String
        var tile: Flavor.RGB?
    }

    private func overviewLines(_ syllabus: Syllabus) -> [OverviewLine] {
        var lines: [OverviewLine] = []
        if let language = syllabus.language { lines.append(OverviewLine(symbol: "globe", text: language.taughtIn)) }
        lines += syllabus.assessment.map { OverviewLine(symbol: "pencil.and.list.clipboard", text: $0) }
        switch PartialExams.policy(assessment: syllabus.assessment, notes: syllabus.assessmentNotes) {
        case .offered:
            lines.append(OverviewLine(symbol: "square.split.2x1", text: String(localized: "Prove in itinere previste"),
                                      tile: Flavor.RGB(red: 0.2, green: 0.62, blue: 0.36)))
        case .none:
            lines.append(OverviewLine(symbol: "square", text: String(localized: "Nessuna prova in itinere"),
                                      tile: ramp.neutral))
        case .unknown:
            break
        }
        return lines
    }

    // MARK: - Building blocks

    /// Inside a card, rows keep off its edge; on a bare page they meet it.
    private var cardPadding: CGFloat { style.material.hasCard ? 14 : 0 }

    private func block<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading(title)
            content()
        }
    }

    /// Rows on one card with hairlines between them, as Oggi's lists are.
    private func rows<Item: Identifiable, Row: View>(
        _ items: [Item], @ViewBuilder row: @escaping (Item, _ last: Bool) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item, item.id == items.last?.id)
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, cardPadding / 2)
        .lookCard()
    }

    /// One of Oggi's rows: a symbol, a line or two, and a value at the end.
    private func row(symbol: String, title: String, detail: String? = nil, trailing: Text? = nil,
                     tile: Flavor.RGB? = nil, last: Bool, chevron: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CourseRowTile(symbol: symbol, colour: tile ?? ramp.main)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let trailing {
                    trailing
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 12)
            if !last {
                Divider().padding(.leading, 42)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The next sitting, large, in the course's colour with Oggi's sheen: the
/// date in the look's typeface, how far off it is, and how it goes.
private struct NextSittingCard: View {
    let exam: ExamSession
    let accent: Color

    @Environment(\.locale) private var locale
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    private var daysAway: Int? {
        guard let date = exam.date else { return nil }
        let calendar = PoliMiDate.romeCalendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now),
                                       to: calendar.startOfDay(for: date)).day
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(exam.date?.formatted(.dateTime.day().month(.abbreviated).locale(locale))
                     ?? String(localized: "Da definire"))
                    .font(style.dateFont.font(size: 40, weight: style.dateWeight))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                if let days = daysAway {
                    Text(days == 0 ? String(localized: "Oggi") : days == 1 ? String(localized: "Domani")
                         : String(localized: "tra \(days) giorni"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: .capsule)
                }
            }
            Text([exam.kind?.nonEmpty,
                  exam.date?.formatted(.dateTime.hour().minute().locale(locale)),
                  exam.room,
                  exam.status.label].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .opacity(0.92)
            if exam.status == .open, let closes = exam.enrolmentCloses {
                Label("Iscrizioni entro il \(closes.formatted(.dateTime.day().month(.wide).locale(locale)))",
                      systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(Theme.onAccent)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(accent)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.glossSheen(.float2(proxy.size), .float(0.5)))
                }
        }
        .shadow(color: accent.opacity(0.3), radius: 10, y: 5)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Apre l’appello")
    }
}

// MARK: - Previews

#Preview("Corso") {
    CourseDetailView(course: MockData.courses[0]).previewInNavigation()
}

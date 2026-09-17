import SwiftUI

/// Everything about one course: where it stands in the libretto, the next
/// lecture and sitting, every part of it one tap away, how the exam works,
/// and what changed.
struct CourseDetailView: View {
    let course: Course

    @Environment(AgendaModel.self) private var agenda
    @Environment(CareerModel.self) private var career
    @Environment(CourseModel.self) private var courses
    @Environment(\.locale) private var locale
    @Environment(UpdateFeed.self) private var feed
    @Environment(ManifestiModel.self) private var manifesti
    @Environment(StudyProgrammeModel.self) private var programmes
    @Environment(Session.self) private var session
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

        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero(next: upcoming.first)
                    hub(reader, hasExams: !sittings.isEmpty)

                    if !lectures.isEmpty {
                        section("Prossime lezioni") {
                            grouped(lectures) { lectureRow($0) }
                        }
                    }

                    if !sittings.isEmpty {
                        section("Appelli") {
                            VStack(spacing: 10) {
                                if let next = upcoming.first {
                                    Button { selectedExam = next } label: { nextSittingCard(next) }
                                        .buttonStyle(.plain)
                                }
                                let others = Array(upcoming.dropFirst()) + past
                                if !others.isEmpty {
                                    grouped(others) { sitting in
                                        Button { selectedExam = sitting } label: { sittingRow(sitting) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .id(Self.examsAnchor)
                    }

                    if let syllabus, !syllabus.isEmpty {
                        section("In breve") { overview(syllabus) }
                    }

                    if !news.isEmpty {
                        section("Novità") {
                            VStack(spacing: 8) {
                                ForEach(news.prefix(3)) { item in
                                    ExamUpdateRow(item: item, isUnread: item.isUnread(since: feed.seenAt))
                                }
                                if news.count > 3 {
                                    NavigationLink { ExamUpdatesView() } label: {
                                        Label("Tutte le novità esami", systemImage: "bell.badge")
                                            .font(.subheadline.weight(.medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .cardBackground()
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    courses.toggleFavourite(course)
                } label: {
                    Image(systemName: course.isFavourite ? "star.fill" : "star")
                        .foregroundStyle(course.isFavourite ? .yellow : accent)
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

    private static let examsAnchor = "appelli"

    // MARK: - Hero

    private func hero(next: ExamSession?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Text(monogram)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 60, height: 60)
                    .background(accent.gradient, in: .rect(cornerRadius: 18))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name)
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .fixedSize(horizontal: false, vertical: true)
                    // The lecturer of the student's bracket, once the plan
                    // says who: a WeBeep course alone carries no teacher.
                    Text(bracketTeacher ?? course.teacher)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips }
                VStack(alignment: .leading, spacing: 6) { chips }
            }

            standing(next: next)

            if let email = course.teacherEmail, let url = URL(string: "mailto:\(email)") {
                Link(destination: url) {
                    Label("Scrivi al docente", systemImage: "envelope.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(accent.opacity(0.14), in: .capsule)
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(RadialGradient(colors: [accent.opacity(0.3), accent.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: 140))
                        .frame(width: 260, height: 260)
                        .offset(x: 90, y: -110)
                }
                .clipShape(.rect(cornerRadius: Theme.cardCorner))
        }
    }

    @ViewBuilder
    private var chips: some View {
        if course.cfu > 0 { chip("\(course.cfu) CFU", "graduationcap") }
        if course.semester != "—" { chip("Semestre \(course.semester)", "calendar") }
        chip("A.A. \(course.academicYear)", "clock.arrow.circlepath")
    }

    /// Where the student is with this course: passed, or the sitting ahead.
    @ViewBuilder
    private func standing(next: ExamSession?) -> some View {
        if let entry = librettoEntry, entry.isPassed {
            statusStrip(icon: "checkmark.seal.fill", tint: .green,
                        title: String(localized: "Superato"),
                        detail: entry.date.map { $0.formatted(.dateTime.day().month(.wide).year().locale(locale)) },
                        value: entry.displayGrade == "—" ? nil : entry.displayGrade)
        } else if let next, let date = next.date {
            let days = PoliMiDate.romeCalendar.dateComponents(
                [.day], from: PoliMiDate.romeCalendar.startOfDay(for: .now),
                to: PoliMiDate.romeCalendar.startOfDay(for: date)).day ?? 0
            statusStrip(icon: "pencil.and.list.clipboard", tint: ExamDetailView.accent(for: next.status),
                        title: next.status.label,
                        detail: String(localized: "Appello del \(date.formatted(.dateTime.day().month(.wide).locale(locale)))"),
                        value: days == 0 ? String(localized: "Oggi") : String(localized: "\(days) gg"))
        }
    }

    private func statusStrip(icon: String, tint: Color, title: String, detail: String?, value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
        }
        .padding(12)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 16))
    }

    private var monogram: String {
        let skip: Set<String> = ["di", "dei", "del", "della", "delle", "e", "ed", "per", "a", "and", "of", "the", "in"]
        return String(course.name
            .split(whereSeparator: { !$0.isLetter })
            .filter { !skip.contains($0.lowercased()) }
            .prefix(2)
            .compactMap(\.first)).uppercased()
    }

    // MARK: - Hub

    /// The course in one place: every part of it one tap from the top.
    private func hub(_ reader: ScrollViewProxy, hasExams: Bool) -> some View {
        let badges = CourseHubBadges(items: FeedItem.items(from: feed.recent, for: course), seenAt: feed.seenAt)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            NavigationLink { CourseForumsView(course: course, kind: .announcements) } label: {
                tile("Avvisi", "megaphone.fill", badge: badges.announcements)
            }
            NavigationLink { CourseMaterialsView(course: course) } label: {
                tile("Materiali", "folder.fill", badge: badges.materials)
            }
            Button {
                withAnimation { reader.scrollTo(Self.examsAnchor, anchor: .top) }
            } label: {
                tile("Appelli", "pencil.and.list.clipboard", badge: badges.exams)
            }
            .disabled(!hasExams)
            NavigationLink { CourseForumsView(course: course, kind: .discussion) } label: {
                tile("Forum", "bubble.left.and.bubble.right.fill")
            }
            NavigationLink { CourseSyllabusView(course: course) } label: {
                tile("Programma", "book.closed.fill")
            }
            NavigationLink { CourseInfoView(course: course) } label: {
                tile("Info", "info.circle.fill")
            }
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: LocalizedStringKey, _ icon: String, badge: Int = 0) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.13), in: .circle)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text(badge, format: .number)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: .capsule)
                    .padding(8)
                    .accessibilityLabel(Text("\(badge) non lette"))
            }
        }
        .contentShape(.rect)
    }

    // MARK: - Lectures

    private func lectureRow(_ lecture: AgendaEvent) -> some View {
        let live = lecture.start <= .now
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(lecture.start.formatted(.dateTime.hour().minute().locale(locale)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(lecture.end.formatted(.dateTime.hour().minute().locale(locale)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 52)

            RoundedRectangle(cornerRadius: 2)
                .fill(live ? .green : accent)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(live ? String(localized: "In corso") : dayLabel(lecture.start))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(live ? .green : .primary)
                Text(lecture.room ?? lecture.roomAcronym ?? String(localized: "Aula da definire"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: lecture.kind.icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = PoliMiDate.romeCalendar
        if calendar.isDateInToday(date) { return String(localized: "Oggi") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Domani") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalized
    }

    // MARK: - Sittings

    private func nextSittingCard(_ exam: ExamSession) -> some View {
        let tint = ExamDetailView.accent(for: exam.status)
        return HStack(spacing: 14) {
            if let date = exam.date {
                VStack(spacing: 0) {
                    Text(date.formatted(.dateTime.month(.abbreviated).locale(locale)).uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(tint)
                    Text(date.formatted(.dateTime.day().locale(locale)))
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .padding(.vertical, 4)
                }
                .frame(width: 58)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prossimo appello")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text([exam.kind?.nonEmpty, exam.date?.formatted(.dateTime.hour().minute().locale(locale))]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(exam.status.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.15), in: .capsule)
                        .foregroundStyle(tint)
                    if let room = exam.room {
                        Label(room, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if exam.status == .open, let closes = exam.enrolmentCloses {
                    Text("Iscrizioni entro il \(closes.formatted(.dateTime.day().month(.wide).locale(locale)))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .contentShape(.rect)
    }

    private func sittingRow(_ sitting: ExamSession) -> some View {
        let tint = ExamDetailView.accent(for: sitting.status)
        return HStack(spacing: 12) {
            Group {
                if let grade = sitting.grade {
                    Text(grade.display)
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Image(systemName: "calendar").foregroundStyle(tint)
                }
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(sitting.date?.formatted(.dateTime.day().month(.wide).year().locale(locale))
                     ?? String(localized: "Data da definire"))
                    .font(.subheadline.weight(.medium))
                Text(sitting.grade.map { $0.passed ? String(localized: "Superato") : String(localized: "Non superato") }
                     ?? sitting.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(.rect)
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
                                .font(.subheadline.weight(.bold))
                                .fontDesign(.rounded)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(label).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    }
                }
            }

            if let language = syllabus.language {
                Label(language.taughtIn, systemImage: "globe").font(.subheadline)
            }
            ForEach(syllabus.assessment, id: \.self) { item in
                Label(item, systemImage: "pencil.and.list.clipboard").font(.subheadline)
            }
            switch PartialExams.policy(assessment: syllabus.assessment, notes: syllabus.assessmentNotes) {
            case .offered:
                Label("Prove in itinere previste", systemImage: "square.split.2x1")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.green)
            case .none:
                Label("Nessuna prova in itinere", systemImage: "square")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .unknown:
                EmptyView()
            }
            if let objectives = syllabus.objectives?.nonEmpty {
                Text(objectives)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            NavigationLink { CourseSyllabusView(course: course) } label: {
                HStack {
                    Label("Programma, libri e dettagli", systemImage: "book.closed")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Building blocks

    private func chip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.15), in: .capsule)
            .foregroundStyle(accent)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
    }

    /// Rows in one card with hairlines between them, like a grouped list.
    private func grouped<Item: Identifiable, Row: View>(
        _ items: [Item], @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 { Divider().padding(.leading, 64) }
            }
        }
        .cardBackground()
    }
}

// MARK: - Previews

#Preview("Corso") {
    CourseDetailView(course: MockData.courses[0]).previewInNavigation()
}

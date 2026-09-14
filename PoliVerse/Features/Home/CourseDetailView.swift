import SwiftUI

/// Everything about one course: next lecture, exam sittings, materials, teacher.
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
    @State private var selectedExam: ExamSession?

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
            .prefix(3)
            .map { $0 }
    }

    private var examSessions: [ExamSession] {
        career.sessions
            .filter { $0.courseCode == course.id }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                hub(reader)

                if !lectures.isEmpty {
                    section("Prossime lezioni") {
                        ForEach(lectures) { lecture in
                            row(
                                title: lecture.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalized,
                                subtitle: "\(lecture.start.formatted(.dateTime.hour().minute().locale(locale))) · \(lecture.room ?? lecture.roomAcronym ?? "Aula da definire")",
                                icon: "clock"
                            )
                        }
                    }
                }

                if !examSessions.isEmpty {
                    section("Appelli") {
                        ForEach(examSessions) { exam in
                            Button { selectedExam = exam } label: {
                                row(
                                    title: exam.date?.formatted(.dateTime.day().month(.wide).year().locale(locale)) ?? "Data da definire",
                                    subtitle: exam.status.label,
                                    icon: "pencil.and.list.clipboard",
                                    chevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .id(Self.examsAnchor)
                }

                let news = FeedItem.items(from: feed.recent, for: course)
                if !news.isEmpty {
                    section("Novità") {
                        ForEach(news.prefix(3)) { item in
                            ExamUpdateRow(item: item, isUnread: item.isUnread(since: feed.seenAt))
                        }
                        if news.count > 3 {
                            NavigationLink {
                                ExamUpdatesView()
                            } label: {
                                row(title: String(localized: "Tutte le novità esami"),
                                    subtitle: String(localized: "Di tutti i corsi"),
                                    icon: "bell.badge", chevron: true)
                            }
                            .buttonStyle(.plain)
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
            programmes.prefetch(teachingCode: course.teachingCode, name: course.name, yearCode: course.academicYearStart)
            await lectures
        }
    }

    private static let examsAnchor = "appelli"

    /// The course in one place: every part of it one tap from the top.
    private func hub(_ reader: ScrollViewProxy) -> some View {
        let badges = CourseHubBadges(items: FeedItem.items(from: feed.recent, for: course), seenAt: feed.seenAt)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
            NavigationLink { CourseForumsView(course: course, kind: .announcements) } label: {
                tile("Avvisi", "megaphone.fill", badge: badges.announcements)
            }
            NavigationLink { CourseForumsView(course: course, kind: .discussion) } label: {
                tile("Forum", "bubble.left.and.bubble.right.fill")
            }
            NavigationLink { CourseMaterialsView(course: course) } label: {
                tile("Materiali", "folder.fill", badge: badges.materials)
            }
            NavigationLink { CourseSyllabusView(course: course) } label: {
                tile("Programma", "book.closed.fill")
            }
            NavigationLink { CourseInfoView(course: course) } label: {
                tile("Info", "info.circle.fill")
            }
            Button {
                withAnimation { reader.scrollTo(Self.examsAnchor, anchor: .top) }
            } label: {
                tile("Appelli", "pencil.and.list.clipboard", badge: badges.exams)
            }
            .disabled(examSessions.isEmpty)
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: LocalizedStringKey, _ icon: String, badge: Int = 0) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.vertical, 6)
        .cardBackground()
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text(badge, format: .number)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: .capsule)
                    .padding(6)
                    .accessibilityLabel(Text("\(badge) non lette"))
            }
        }
        .contentShape(.rect)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(course.name)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .fixedSize(horizontal: false, vertical: true)

            Text(course.teacher)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if course.cfu > 0 { chip("\(course.cfu) CFU", "graduationcap") }
                if course.semester != "—" { chip("Semestre \(course.semester)", "calendar") }
                chip("A.A. \(course.academicYear)", "clock.arrow.circlepath")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(RadialGradient(
                            colors: [accent.opacity(0.32), accent.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 130))
                        .frame(width: 220, height: 220)
                        .offset(x: 70, y: -90)
                }
                .clipShape(.rect(cornerRadius: Theme.cardCorner))
        }
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.15), in: .capsule)
            .foregroundStyle(accent)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) { content() }
        }
    }

    private func row(title: String, subtitle: String, icon: String, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

// MARK: - Previews

#Preview("Corso") {
    CourseDetailView(course: MockData.courses[0]).previewInNavigation()
}

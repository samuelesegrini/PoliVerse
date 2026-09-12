import SwiftUI

/// One field over everything the app already holds.
///
/// Deliberately searches what is **in memory**, never the network: a search
/// box that pauses to fetch is a search box nobody uses. That shapes what is
/// findable — WeBeep materials are searched across the courses already opened,
/// because reaching the rest would mean 22 requests per keystroke, and the
/// footer says so rather than leaving the gap to be discovered.
struct SearchView: View {
    @Environment(CourseService.self) private var courses
    @Environment(AgendaService.self) private var agenda
    @Environment(CareerService.self) private var career
    @Environment(RoomsService.self) private var rooms
    @Environment(NewsService.self) private var news
    @Environment(NoticeService.self) private var notices
    @Environment(WeBeepService.self) private var weBeep
    @Environment(\.locale) private var locale

    @State private var query = ""

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchedCourses: [Course] {
        guard !trimmed.isEmpty else { return [] }
        return courses.courses.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.teacher.localizedCaseInsensitiveContains(trimmed)
                || $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var matchedEvents: [AgendaEvent] {
        guard !trimmed.isEmpty else { return [] }
        return agenda.events
            .filter { $0.end > .now }
            .filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || ($0.room ?? "").localizedCaseInsensitiveContains(trimmed)
                    || ($0.roomAcronym ?? "").localizedCaseInsensitiveContains(trimmed)
            }
            .prefix(10)
            .map { $0 }
    }

    private var matchedExams: [ExamSession] {
        guard !trimmed.isEmpty else { return [] }
        return career.sessions.filter {
            $0.courseName.localizedCaseInsensitiveContains(trimmed)
                || ($0.room ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var matchedRooms: [Classroom] {
        guard trimmed.count >= 2 else { return [] }
        return Array(rooms.rooms(matching: trimmed, campus: nil).prefix(8))
    }

    private var matchedTeachers: [Teacher] {
        guard trimmed.count >= 2 else { return [] }
        return Teacher.roster(courses: courses.courses, sessions: career.sessions)
            .filter { $0.matches(trimmed) }
            .prefix(8)
            .map { $0 }
    }

    private var matchedNews: [NewsItem] {
        guard trimmed.count >= 2 else { return [] }
        return news.items.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.summary ?? "").localizedCaseInsensitiveContains(trimmed)
        }.prefix(6).map { $0 }
    }

    private var matchedNotices: [Notice] {
        guard trimmed.count >= 2 else { return [] }
        return notices.notices.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.body ?? "").localizedCaseInsensitiveContains(trimmed)
        }.prefix(6).map { $0 }
    }

    private var matchedFiles: [WeBeepFile] {
        guard trimmed.count >= 2 else { return [] }
        return weBeep.sections
            .flatMap(\.files)
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .prefix(8)
            .map { $0 }
    }

    private var isEmpty: Bool {
        matchedCourses.isEmpty && matchedEvents.isEmpty
            && matchedExams.isEmpty && matchedRooms.isEmpty
            && matchedTeachers.isEmpty && matchedNews.isEmpty
            && matchedNotices.isEmpty && matchedFiles.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmed.isEmpty {
                    Section {
                        NavigationLink {
                            RoomsView()
                        } label: {
                            Label("Aule", systemImage: "building.2")
                        }
                        NavigationLink {
                            CampusMapView()
                        } label: {
                            Label("Mappa del campus", systemImage: "map")
                        }
                        NavigationLink {
                            StudyPlanView()
                        } label: {
                            Label("Piano di studi", systemImage: "list.bullet.rectangle")
                        }
                        NavigationLink {
                            GradeSimulatorView()
                        } label: {
                            Label("Simulazione media", systemImage: "function")
                        }
                    }
                }

                if !matchedTeachers.isEmpty {
                    Section("Docenti") {
                        ForEach(matchedTeachers) { teacher in
                            NavigationLink {
                                TeacherDetailView(teacher: teacher)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(teacher.name).font(.subheadline.weight(.medium))
                                    Text(teacher.courses.isEmpty
                                         ? (teacher.email ?? "—")
                                         : "\(teacher.courses.count) insegnamenti")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !matchedRooms.isEmpty {
                    Section("Aule") {
                        ForEach(matchedRooms) { room in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.id).font(.subheadline.weight(.medium)).monospaced()
                                Text(room.locationLabel.isEmpty
                                     ? "\(room.capacity) posti"
                                     : "\(room.locationLabel) · \(room.capacity) posti")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !matchedCourses.isEmpty {
                    Section("Corsi") {
                        ForEach(matchedCourses) { course in
                            NavigationLink(value: course) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.name).font(.subheadline.weight(.medium))
                                    Text(course.teacher).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !matchedEvents.isEmpty {
                    Section("In calendario") {
                        ForEach(matchedEvents) { event in
                            HStack(spacing: 10) {
                                Image(systemName: event.kind.icon)
                                    .foregroundStyle(Theme.brand)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).font(.subheadline).lineLimit(2)
                                    Text("\(event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))) · \(event.start.formatted(.dateTime.hour().minute().locale(locale)))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !matchedExams.isEmpty {
                    Section("Appelli") {
                        ForEach(matchedExams) { exam in
                            HStack(spacing: 10) {
                                Image(systemName: "pencil.and.list.clipboard")
                                    .foregroundStyle(Theme.brand)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exam.courseName).font(.subheadline).lineLimit(2)
                                    Text(exam.grade.map { "Esito: \($0.display)" }
                                        ?? exam.date?.formatted(.dateTime.day().month(.wide).locale(locale))
                                        ?? exam.status.label)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !matchedFiles.isEmpty {
                    Section {
                        ForEach(matchedFiles) { file in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).font(.subheadline).lineLimit(2)
                                Text(file.sectionName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Materiali")
                    } footer: {
                        Text("Solo i corsi WeBeep già aperti: cercarli tutti richiederebbe una richiesta per corso.")
                    }
                }

                if !matchedNews.isEmpty {
                    Section("Notizie") {
                        ForEach(matchedNews) { item in
                            NavigationLink {
                                NewsDetailView(item: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline).lineLimit(2)
                                    if let date = item.displayDate {
                                        Text(date.formatted(.relative(presentation: .named)))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if !matchedNotices.isEmpty {
                    Section("Notifiche") {
                        ForEach(matchedNotices) { notice in
                            NavigationLink {
                                NoticeDetailView(notice: notice)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(notice.title).font(.subheadline).lineLimit(2)
                                    if let date = notice.date {
                                        Text(date.formatted(.relative(presentation: .named)))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cerca")
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .searchable(text: $query, prompt: "Corsi, docenti, aule, notizie, materiali")
            .overlay {
                if isEmpty && !trimmed.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
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
}

// MARK: - Previews

#Preview("Cerca") {
    SearchView().previewEnvironment()
}

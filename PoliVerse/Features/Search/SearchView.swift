import CoreSpotlight
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
    @State private var scope: Scope = .all
    @State private var spotlightCourse: Course?
    @State private var spotlightRoom: Classroom?
    @State private var spotlightTeacher: Teacher?

    /// What the results are narrowed to.
    ///
    /// Scopes rather than more sections: with eight kinds of result, a query
    /// like "analisi" fills the screen and the thing being looked for is
    /// below the fold. Choosing a kind is faster than scrolling past seven.
    nonisolated enum Scope: String, CaseIterable, Identifiable {
        case all, teaching, places, people, content
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "Tutto"
            case .teaching: "Didattica"
            case .places: "Luoghi"
            case .people: "Persone"
            case .content: "Contenuti"
            }
        }
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shows(_ scope: Scope) -> Bool {
        self.scope == .all || self.scope == scope
    }

    /// Suggestions offered before anything is typed, and completions after.
    /// Drawn from what is loaded, so they can never suggest a dead end.
    private var suggestions: [String] {
        guard trimmed.count >= 2 else { return [] }
        let pool = courses.courses.map(\.name)
            + rooms.rooms.prefix(200).map(\.id)
            + Teacher.roster(courses: courses.courses, sessions: career.sessions).map(\.name)
        return Array(SearchMatch.rank(pool, query: trimmed) { [$0] }
            .filter { $0.lowercased() != trimmed.lowercased() }
            .prefix(4))
    }

    private var matchedCourses: [Course] {
        guard !trimmed.isEmpty, shows(.teaching) else { return [] }
        return SearchMatch.rank(courses.courses, query: trimmed) {
            [$0.name, $0.teacher, $0.code ?? "", $0.academicYear]
        }
    }

    private var matchedEvents: [AgendaEvent] {
        guard !trimmed.isEmpty, shows(.teaching) else { return [] }
        let upcoming = agenda.events.filter { $0.end > .now }
        return Array(SearchMatch.rank(upcoming, query: trimmed) {
            [$0.title, $0.room ?? "", $0.roomAcronym ?? ""]
        }.prefix(10))
    }

    private var matchedExams: [ExamSession] {
        guard !trimmed.isEmpty, shows(.teaching) else { return [] }
        return SearchMatch.rank(career.sessions, query: trimmed) {
            [$0.courseName, $0.room ?? "", $0.teacher ?? ""]
        }
    }

    private var matchedRooms: [Classroom] {
        guard trimmed.count >= 2, shows(.places) else { return [] }
        return Array(SearchMatch.rank(rooms.rooms, query: trimmed) {
            [$0.id, $0.buildingName ?? "", $0.campusName ?? "", $0.address ?? ""]
        }.prefix(8))
    }

    private var matchedTeachers: [Teacher] {
        guard trimmed.count >= 2, shows(.people) else { return [] }
        let roster = Teacher.roster(courses: courses.courses, sessions: career.sessions)
        return Array(SearchMatch.rank(roster, query: trimmed) {
            [$0.name, $0.email ?? ""]
        }.prefix(8))
    }

    private var matchedNews: [NewsItem] {
        guard trimmed.count >= 2, shows(.content) else { return [] }
        return Array(SearchMatch.rank(news.items, query: trimmed) {
            [$0.title, $0.summary ?? "", $0.category ?? ""]
        }.prefix(6))
    }

    private var matchedNotices: [Notice] {
        guard trimmed.count >= 2, shows(.content) else { return [] }
        return Array(SearchMatch.rank(notices.notices, query: trimmed) {
            [$0.title, $0.body ?? "", $0.category ?? ""]
        }.prefix(6))
    }

    private var matchedFiles: [WeBeepFile] {
        guard trimmed.count >= 2, shows(.content) else { return [] }
        return Array(SearchMatch.rank(weBeep.sections.flatMap(\.files), query: trimmed) {
            [$0.name, $0.sectionName]
        }.prefix(8))
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
            // Donated so the screen can be handed off and offered as a
            // suggestion. The query travels with it; nothing else does.
            .userActivity(SpotlightIndex.activityType) { activity in
                activity.title = trimmed.isEmpty ? "Cerca in PoliVerse" : "Cerca “\(trimmed)”"
                activity.isEligibleForHandoff = true
                activity.isEligibleForPrediction = true
                activity.userInfo = ["query": trimmed]
            }
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .searchable(text: $query, prompt: "Corsi, docenti, aule, notizie, materiali")
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(Scope.allCases) { Text($0.label).tag($0) }
            }
            .searchSuggestions {
                // Completions drawn from loaded data, so a suggestion can
                // never lead to an empty screen.
                ForEach(suggestions, id: \.self) { suggestion in
                    Text(suggestion).searchCompletion(suggestion)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .overlay {
                if isEmpty && !trimmed.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
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

// MARK: - Previews

#Preview("Cerca") {
    SearchView().previewEnvironment()
}

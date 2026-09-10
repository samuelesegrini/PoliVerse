import SwiftUI

/// Search across courses, agenda entries and exam sittings at once.
struct SearchView: View {
    @Environment(CourseService.self) private var courses
    @Environment(AgendaService.self) private var agenda
    @Environment(CareerService.self) private var career
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

    private var isEmpty: Bool {
        matchedCourses.isEmpty && matchedEvents.isEmpty && matchedExams.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
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
            }
            .navigationTitle("Cerca")
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .searchable(text: $query, prompt: "Corsi, docenti, aule, appelli")
            .overlay {
                if trimmed.isEmpty {
                    ContentUnavailableView(
                        "Cerca", systemImage: "magnifyingglass",
                        description: Text("Corsi, docenti, lezioni, aule e appelli.")
                    )
                } else if isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
            .task {
                await courses.load()
                await agenda.load(from: .now)
                await career.load()
            }
        }
    }
}

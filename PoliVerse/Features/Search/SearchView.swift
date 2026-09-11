import SwiftUI

/// Search across courses, agenda entries and exam sittings at once.
struct SearchView: View {
    @Environment(CourseService.self) private var courses
    @Environment(AgendaService.self) private var agenda
    @Environment(CareerService.self) private var career
    @Environment(RoomsService.self) private var rooms
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

    private var isEmpty: Bool {
        matchedCourses.isEmpty && matchedEvents.isEmpty
            && matchedExams.isEmpty && matchedRooms.isEmpty
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
            }
            .navigationTitle("Cerca")
            .navigationDestination(for: Course.self) { CourseDetailView(course: $0) }
            .searchable(text: $query, prompt: "Corsi, docenti, aule, appelli")
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
            }
        }
    }
}

import SwiftUI

/// A teacher, their courses, and when they next teach.
///
/// The timetable link is the point: "where is Rossi teaching on Thursday" is a
/// question the agenda can already answer, it was just never asked this way
/// round. Lectures are matched to the teacher through their courses, since the
/// agenda names the teaching, not the person.
struct TeacherDetailView: View {
    let teacher: Teacher

    @Environment(AgendaModel.self) private var agenda
    @Environment(CareerModel.self) private var career
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    /// Upcoming lectures for any of this teacher's courses.
    private var lectures: [AgendaEvent] {
        let names = Set(teacher.courses.map { $0.name.lowercased() })
        guard !names.isEmpty else { return [] }
        return agenda.events
            .filter { $0.end > .now }
            .filter { event in
                names.contains { event.title.lowercased().contains($0) }
            }
            .sorted { $0.start < $1.start }
            .prefix(10)
            .map { $0 }
    }

    private var exams: [ExamSession] {
        career.upcoming.filter { session in
            teacher.courses.contains { $0.name.lowercased() == session.courseName.lowercased() }
        }
    }

    var body: some View {
        List {
            Section {
                PageHero(symbol: "person", title: Text(verbatim: teacher.name), summary: teacher.courses.isEmpty ? nil : Text("\(teacher.courses.count) insegnamenti"))
                    .listHeader()
            }
            if let email = teacher.email {
                Section {
                    Button {
                        if let url = URL(string: "mailto:\(email)") { openURL(url) }
                    } label: {
                        Label(email, systemImage: "envelope")
                    }
                }
                .glassRow()
            }

            if !teacher.courses.isEmpty {
                Section("Insegnamenti") {
                    ForEach(teacher.courses) { course in
                        NavigationLink {
                            CourseDetailView(course: course)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).font(.subheadline)
                                Text(course.academicYear)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .glassRow()
            }

            Section {
                if lectures.isEmpty {
                    Text("Nessuna lezione nel periodo caricato.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lectures) { event in
                        NavigationLink {
                            EventDetailView(event: event)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(.subheadline).lineLimit(2)
                                Text("\(event.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale))) · \(event.start.formatted(.dateTime.hour().minute().locale(locale)))\(event.room.map { " · \($0)" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Prossime lezioni")
            } footer: {
                // Said plainly: the agenda names teachings, not people, so a
                // course taught by two people shows both their lectures.
                Text("Le lezioni sono ricavate dai suoi insegnamenti nel tuo orario.")
            }
            .glassRow()

            if !exams.isEmpty {
                Section("Appelli") {
                    ForEach(exams) { exam in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exam.courseName).font(.subheadline)
                            Text(exam.date?.formatted(date: .long, time: .shortened) ?? "—")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .glassRow()
            }
        }
        .glassList()
        .navigationTitle(teacher.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#Preview("Docente") {
    TeacherDetailView(
        teacher: Teacher.roster(courses: Course.samples,
                                sessions: ExamSession.samples())[0])
        .previewInNavigation()
}

import SwiftUI

/// The facts of a course in one place: credits, teacher, how the exam works,
/// and prove in itinere.
struct CourseInfoView: View {
    let course: Course

    @Environment(ManifestiService.self) private var manifesti
    @Environment(StudyProgrammeService.self) private var programmes
    @Environment(Session.self) private var session
    @Environment(CareerService.self) private var career
    @Environment(AgendaService.self) private var agenda
    @Environment(UpdateFeed.self) private var feed
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var syllabus: Syllabus?
    @State private var pickTeachers: String?
    @State private var pickBracket: String?
    @State private var loading = true

    private var partialSittings: [ExamSession] {
        PartialExams.sittings(career.sessions.filter { $0.isOf(courseCode: course.id, courseName: course.name) })
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Agenda exams of this course named as partial exams, matched by title
    /// like the course page's lectures.
    private var partialEvents: [AgendaEvent] {
        let target = course.name.lowercased()
        return PartialExams.agendaEvents(agenda.officialEvents.filter { event in
            // One way only: a generic agenda title ("Esame") must not
            // attach to every course whose name contains it.
            event.title.lowercased().contains(target)
        })
    }

    private var partialResults: [ExamUpdate] {
        PartialExams.resultsFiles(FeedItem.items(from: feed.recent, for: course).map(\.update))
    }

    var body: some View {
        List {
            Section {
                if course.cfu > 0 { LabeledContent("Crediti", value: "\(course.cfu) CFU") }
                if course.semester != "—" { LabeledContent("Semestre", value: course.semester) }
                LabeledContent("Anno accademico", value: course.academicYear)
                if let code = course.teachingCode { LabeledContent("Codice", value: code) }
            }

            Section("Docente") {
                Text(pickTeachers ?? course.teacher)
                if let bracket = pickBracket {
                    LabeledContent("Scaglione", value: bracket)
                }
                if let email = course.teacherEmail, !email.isEmpty, let url = URL(string: "mailto:\(email)") {
                    Button { openURL(url) } label: { Label(email, systemImage: "envelope") }
                }
            }

            if let syllabus, !syllabus.assessment.isEmpty {
                Section("Esame") {
                    ForEach(syllabus.assessment, id: \.self) { Text($0) }
                }
            }

            partialExamsSection
        }
        .navigationTitle("Informazioni")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await agenda.load(around: .now)
            do {
                let pick = await programmes.pick(teachingCode: course.teachingCode, name: course.name, yearCode: course.academicYearStart, courseID: course.id)
                // Only from the student's own plan: the catalogue-wide fallback
                // may be another degree course, with other lecturers.
                if let pick, pick.matchesDegree {
                    let module = pick.module
                    if !pick.teachers.isEmpty { pickTeachers = pick.teachers.joined(separator: ", ") }
                    if let from = module.scaglioneFrom, let to = module.scaglioneTo, from != "A" || to != "ZZZZ" {
                        pickBracket = "\(from) – \(to)"
                    }
                }
                if let id = pick?.module.syllabusID { syllabus = await manifesti.syllabus(for: id) }
            }
            loading = false
        }
    }

    @ViewBuilder
    private var partialExamsSection: some View {
        let policy = syllabus.map { PartialExams.policy(assessment: $0.assessment, notes: $0.assessmentNotes) } ?? .unknown
        let quotes = PartialExams.sentences(in: syllabus?.assessmentNotes)
        Section {
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                switch policy {
                case .offered: Label("Previste", systemImage: "checkmark.circle").foregroundStyle(.green)
                case .none: Label("Non previste", systemImage: "xmark.circle").foregroundStyle(.secondary)
                case .unknown: Label("La scheda non lo dice", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                }
            }
            ForEach(quotes, id: \.self) { quote in
                Text("«\(quote)»").font(.callout).italic()
            }
            ForEach(partialEvents) { event in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.subheadline.weight(.medium))
                        Text([event.start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(locale)),
                              event.room].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "calendar")
                }
            }
            ForEach(partialResults) { update in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.newValue ?? "").font(.subheadline.weight(.medium))
                        if let grade = update.lookup?.grade {
                            Text("Nel file: \(grade) (non ancora ufficiale)").font(.caption).foregroundStyle(.secondary)
                        } else if update.lookup?.looksLikeResults == true {
                            Text("Non ho trovato la tua riga nel file").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "tablecells")
                }
            }
            ForEach(partialSittings) { sitting in
                VStack(alignment: .leading, spacing: 2) {
                    Text(sitting.kind ?? "")
                        .font(.subheadline.weight(.medium))
                    Text([sitting.date?.formatted(.dateTime.day().month(.wide).year().locale(locale)),
                          sitting.grade.map { String(localized: "Esito: \($0.display)") } ?? sitting.status.label]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Prove in itinere")
        } footer: {
            Text("Dalla scheda dell'insegnamento e dagli appelli. Come le prove contano sul voto lo decide il docente: fa fede il suo testo.")
        }
    }
}

#Preview("Informazioni corso") {
    CourseInfoView(course: MockData.courses[0]).previewInNavigation()
}

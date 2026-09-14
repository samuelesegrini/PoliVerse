import SwiftUI

/// The facts of a course in one place: credits, teacher, how the exam works,
/// and prove in itinere.
struct CourseInfoView: View {
    let course: Course

    @Environment(ManifestiService.self) private var manifesti
    @Environment(Session.self) private var session
    @Environment(CareerService.self) private var career
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var syllabus: Syllabus?
    @State private var loading = true

    private var partialSittings: [ExamSession] {
        PartialExams.sittings(career.sessions.filter { $0.isOf(courseCode: course.id, courseName: course.name) })
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
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
                Text(course.teacher)
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
            if let code = course.teachingCode {
                let pick = await manifesti.syllabusPick(
                    teachingCode: code, surname: session.student?.lastName,
                    degreeName: career.planHeader?.course, yearCode: course.academicYearStart)
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

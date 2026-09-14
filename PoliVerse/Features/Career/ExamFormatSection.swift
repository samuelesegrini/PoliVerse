import SwiftUI

/// How a sitting's exam works, from the teaching's scheda: written or oral,
/// with or without midterms, and whether it can be taken in English.
///
/// Shown in the exam sheet because that is where a student looks before
/// sitting it. Nothing is shown when the scheda cannot be found — the sheet
/// is about the sitting, and a "not found" there would be noise.
struct ExamFormatSection: View {
    let exam: ExamSession

    @Environment(ManifestiService.self) private var manifesti
    @Environment(Session.self) private var session
    @Environment(CareerService.self) private var career
    @State private var syllabus: Syllabus?
    @State private var classID: String?

    var body: some View {
        Group {
            if let syllabus, !syllabus.assessment.isEmpty || syllabus.language != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Come si svolge")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(syllabus.assessment, id: \.self) { item in
                            Label(item, systemImage: "pencil.and.list.clipboard")
                                .font(.subheadline)
                        }
                        if let language = syllabus.language {
                            Label(language.taughtIn, systemImage: "globe")
                                .font(.subheadline)
                        }
                        if syllabus.language == .italian, syllabus.englishSupport.contains(.exam) {
                            Label(EnglishSupport.exam.label, systemImage: "checkmark")
                                .font(.subheadline)
                        }
                        if let classID {
                            NavigationLink {
                                SyllabusView(classID: classID, title: exam.courseName)
                            } label: {
                                Label("Scheda completa: programma e libri", systemImage: "book.closed")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        Text("Dalla scheda dell'insegnamento nel Manifesto degli studi.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()
                }
            }
        }
        .task {
            // Sample data has invented codes: no catalogue lookups for it.
            guard !session.useMockData else { return }
            // The scheda of the sitting's own academic year: a September
            // sitting belongs to the year that is ending.
            let year = exam.date.map { String(Course.academicYearLabel(for: $0).prefix(4)) }
            let pick = await manifesti.syllabusPick(
                teachingCode: exam.courseCode, surname: session.student?.lastName,
                degreeName: career.planHeader?.course, yearCode: year)
            guard let id = pick?.module.syllabusID else { return }
            classID = id
            syllabus = await manifesti.syllabus(for: id)
        }
    }
}

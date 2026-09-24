import SwiftUI

/// How a sitting's exam works, from the teaching's scheda: written or oral,
/// with or without midterms, the teacher's own words on it, who teaches it
/// and how much study it asks for.
///
/// Shown in the exam sheet because that is where a student looks before
/// sitting it. Nothing is shown when the scheda cannot be found — the sheet
/// is about the sitting, and a "not found" there would be noise.
struct ExamFormatSection: View {
    /// The sitting whose teaching is described.
    let exam: ExamSession

    /// The shared ``ManifestiModel``, from the environment.
    @Environment(ManifestiModel.self) private var manifesti
    /// The shared ``StudyProgrammeModel``, from the environment.
    @Environment(StudyProgrammeModel.self) private var programmes
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    @State private var syllabus: Syllabus?
    @State private var classID: String?
    @State private var notesExpanded = false
    @Environment(\.look) private var style

    /// The view's content.
    var body: some View {
        Group {
            if let syllabus, !syllabus.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    LookHeading("Come si svolge")

                    VStack(alignment: .leading, spacing: 12) {
                        facts(syllabus)

                        ForEach(syllabus.assessment, id: \.self) { item in
                            Label(item, systemImage: "pencil.and.list.clipboard")
                                .font(.subheadline)
                        }

                        partialExams(syllabus)

                        if let language = syllabus.language {
                            Label(language.taughtIn, systemImage: "globe")
                                .font(.subheadline)
                        }
                        if syllabus.language == .italian, syllabus.englishSupport.contains(.exam) {
                            Label(EnglishSupport.exam.label, systemImage: "checkmark")
                                .font(.subheadline)
                        }

                        if let notes = syllabus.assessmentNotes?.nonEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notes)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(notesExpanded ? nil : 4)
                                Button(notesExpanded ? "Mostra meno" : "Leggi tutto") {
                                    withAnimation(.snappy) { notesExpanded.toggle() }
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
                        }

                        if !syllabus.teachers.isEmpty {
                            Label(syllabus.teachers.map(\.name).joined(separator: ", "), systemImage: "person.2")
                                .font(.subheadline)
                        }

                        if let classID {
                            NavigationLink {
                                SyllabusView(classID: classID, title: exam.courseName)
                            } label: {
                                HStack {
                                    Label("Scheda completa: programma e libri", systemImage: "book.closed")
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .font(.subheadline.weight(.medium))
                            }
                        }
                        Text("Dalla scheda dell'insegnamento nel Manifesto degli studi.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lookCard()
                }
            }
        }
        .task(id: exam.id) {
            // Sample data has invented codes: no catalogue lookups for it.
            guard !session.useMockData else { return }
            // The scheda of the sitting's own academic year: a September
            // sitting belongs to the year that is ending — see ``TeachingRef``.
            let pick = await programmes.pick(TeachingRef(exam))
            guard let id = pick?.module.syllabusID else { return }
            classID = id
            syllabus = await manifesti.syllabus(for: id)
        }
    }

    /// Credits, type and study hours as small tiles: numbers read at a glance.
    @ViewBuilder
    private func facts(_ syllabus: Syllabus) -> some View {
        let tiles: [(String, String)] = [
            syllabus.credits.map { ($0.formatted(.number.precision(.fractionLength(0...1))), String(localized: "CFU")) },
            syllabus.assistedMinutes.map { ("\($0 / 60)", String(localized: "ore in aula")) },
            syllabus.selfStudyMinutes.map { ("\($0 / 60)", String(localized: "ore di studio")) },
        ].compactMap { $0 }
        if !tiles.isEmpty {
            HStack(spacing: 8) {
                ForEach(tiles, id: \.1) { value, label in
                    VStack(spacing: 2) {
                        Text(value)
                            .font(style.dateFont.font(size: 20, weight: style.dateWeight))
                            .monospacedDigit()
                        Text(label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    /// Whether prove in itinere are offered, and nothing at all when the scheda does not say.
    ///
    /// - Parameter syllabus: The teaching's scheda.
    /// - Returns: The line, or an empty view.
    @ViewBuilder
    private func partialExams(_ syllabus: Syllabus) -> some View {
        switch PartialExams.policy(assessment: syllabus.assessment, notes: syllabus.assessmentNotes) {
        case .offered:
            Label("Prove in itinere previste", systemImage: "square.split.2x1")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
        case .none:
            Label("Nessuna prova in itinere", systemImage: "square")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .unknown:
            EmptyView()
        }
    }
}

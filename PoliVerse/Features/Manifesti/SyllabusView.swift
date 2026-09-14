import SwiftUI

/// The syllabus: how the exam works, the language, the teachers, the hours,
/// the prose sections and the books.
///
/// A different service again — `schedaincarico` — reached with the `c_classe`
/// the manifesto hides behind an icon. Public, and reachable directly: the
/// catalogue routes it through `aunicalogin`, but that only redirects to the
/// same page with two throwaway tokens, so the app skips the round trip.
struct SyllabusView: View {
    let classID: String
    let title: String

    @Environment(ManifestiService.self) private var manifesti
    @State private var syllabus: Syllabus?
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if let syllabus, !syllabus.isEmpty {
                SyllabusSections(syllabus: syllabus)
            } else {
                Section {
                    // Said plainly: many teachings simply have no published
                    // scheda, which is not the same as a failure.
                    Text("Il Politecnico non pubblica una scheda per questo modulo.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Programma")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            syllabus = await manifesti.syllabus(for: classID)
            loading = false
        }
    }
}

/// The scheda's sections, most practical first: what the exam is, what
/// language it is in, who teaches it and how much time it takes — then the
/// prose and the books.
struct SyllabusSections: View {
    let syllabus: Syllabus

    var body: some View {
        if !syllabus.assessment.isEmpty || syllabus.assessmentNotes != nil {
            Section("Esame") {
                ForEach(syllabus.assessment, id: \.self) { item in
                    Label(item, systemImage: "pencil.and.list.clipboard")
                        .font(.subheadline)
                }
                if let notes = syllabus.assessmentNotes {
                    DisclosureGroup("Come lo descrive il docente") {
                        Text(notes).font(.subheadline).textSelection(.enabled)
                    }
                    .font(.subheadline)
                }
            }
        }

        if syllabus.language != nil || !syllabus.englishSupport.isEmpty {
            Section("Lingua") {
                if let language = syllabus.language {
                    LabeledContent("Erogato in", value: language.label)
                }
                ForEach(syllabus.englishSupport, id: \.self) { support in
                    Label(support.label, systemImage: "checkmark")
                        .font(.subheadline)
                }
            }
        }

        if !syllabus.teachers.isEmpty || syllabus.credits != nil || syllabus.teachingType != nil {
            Section("Insegnamento") {
                ForEach(Array(syllabus.teachers.enumerated()), id: \.element.id) { index, teacher in
                    LabeledContent(index == 0 ? String(localized: "Titolare") : String(localized: "Co-titolare"),
                                   value: teacher.name)
                }
                if let credits = syllabus.credits {
                    LabeledContent("CFU", value: credits.formatted(.number))
                }
                if let type = syllabus.teachingType {
                    LabeledContent("Tipo", value: type)
                }
            }
        }

        if !syllabus.teachingForms.isEmpty || syllabus.selfStudyMinutes != nil {
            Section {
                ForEach(syllabus.teachingForms, id: \.name) { form in
                    LabeledContent(SyllabusSections.formName(form.name), value: SyllabusSections.hours(form.minutes))
                }
                if let assisted = syllabus.assistedMinutes {
                    LabeledContent("In aula, in tutto", value: SyllabusSections.hours(assisted))
                }
                if let study = syllabus.selfStudyMinutes {
                    LabeledContent("Studio autonomo", value: SyllabusSections.hours(study))
                }
            } header: {
                Text("Impegno")
            } footer: {
                Text("Ore indicate dalla scheda del Politecnico.")
            }
        }

        ForEach(syllabus.sections.filter { !$0.title.localizedCaseInsensitiveContains("valutazione") }, id: \.title) { section in
            Section(section.title) {
                Text(section.body)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }

        if !syllabus.books.isEmpty {
            Section("Bibliografia") {
                ForEach(syllabus.books) { book in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(book.title).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(book.isRequired ? String(localized: "Obbligatorio") : String(localized: "Facoltativo"))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background((book.isRequired ? Theme.brand : Color.secondary).opacity(0.15), in: .capsule)
                                .foregroundStyle(book.isRequired ? Theme.brand : .secondary)
                        }
                        if let authors = book.authors { Text(authors).font(.caption) }
                        if let details = book.details {
                            Text(details).font(.caption).foregroundStyle(.secondary)
                        }
                        if let url = book.url {
                            Link(destination: url) {
                                Label("Apri il link", systemImage: "arrow.up.right.square")
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }

        if let software = syllabus.software {
            Section("Software") { Text(software).font(.subheadline) }
        }

        if syllabus.brackets.count > 1 {
            Section {
                ForEach(syllabus.brackets, id: \.self) { bracket in
                    LabeledContent {
                        Text([bracket.from, bracket.to].compactMap { $0 }.joined(separator: " – "))
                            .monospaced()
                    } label: {
                        Text(bracket.degreeCourse).font(.caption)
                    }
                }
            } header: {
                Text("Scaglioni per corso di studi")
            } footer: {
                Text("Dal primo cognome incluso al secondo escluso.")
            }
        }
    }

    /// The service's shouted form names, in words a student uses.
    static func formName(_ raw: String) -> String {
        let key = raw.lowercased()
        if key.contains("frontale") { return String(localized: "Lezioni") }
        if key.contains("laboratorial") { return String(localized: "Laboratorio") }
        if key.contains("progettual") { return String(localized: "Progetto") }
        if key.contains("interattiva") { return String(localized: "Didattica interattiva") }
        if key.contains("valutativa") { return String(localized: "Verifiche") }
        return raw.capitalized
    }

    static func hours(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
    }
}

/// The scheda of one of the student's own courses, found from its code.
struct CourseSyllabusView: View {
    let course: Course

    @Environment(ManifestiService.self) private var manifesti
    @Environment(StudyProgrammeService.self) private var programmes
    @Environment(Session.self) private var session
    @State private var pick: SyllabusPicker.Pick?
    @State private var syllabus: Syllabus?
    @State private var loading = true
    @State private var changingProgramme = false
    @State private var choosingBracket = false

    var body: some View {
        List {
            programmeSection
            if loading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if let syllabus, !syllabus.isEmpty {
                if let pick {
                    Section {
                        if let from = pick.module.scaglioneFrom, let to = pick.module.scaglioneTo, to != "ZZZZ" || from != "A" {
                            LabeledContent("Scaglione", value: "\(from) – \(to)")
                        }
                        if let teachers = pick.module.teachers.map(\.name).nonEmptyJoined {
                            LabeledContent("Docente", value: teachers)
                        }
                        if programmes.programme != nil {
                            Button("Scegli un altro scaglione") { choosingBracket = true }
                        }
                    } footer: {
                        // Which row was chosen: from the plan when there is
                        // one, a guess otherwise — say which.
                        if pick.matchesDegree {
                            Text("Scheda del tuo piano di studi, nello scaglione del tuo cognome o in quello che hai scelto.")
                        } else {
                            Text("Il tuo corso di studi non risulta tra quelli che offrono questo insegnamento: questa è la scheda del primo che lo offre. Controlla che sia la tua.")
                        }
                    }
                }
                SyllabusSections(syllabus: syllabus)
            } else {
                Section {
                    Text(programmes.programme == nil && course.teachingCode == nil
                         ? "Questo corso non ha un codice d'insegnamento: scegli il tuo corso di studi per trovarlo nel tuo piano."
                         : "Non trovo la scheda di questo insegnamento nel Manifesto degli studi.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Programma")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: programmes.programme) { await load() }
        .sheet(isPresented: $changingProgramme) { StudyProgrammeSheet() }
        .sheet(isPresented: $choosingBracket) {
            BracketPicker(title: course.name, surname: session.student?.lastName ?? "",
                          chosen: bracketCode.flatMap { programmes.programme?.brackets[$0] },
                          load: { await programmes.brackets(teachingCode: course.teachingCode, name: course.name,
                                                            yearCode: course.academicYearStart)?.1 ?? [] },
                          onChoose: { bracket in
                              if let code = bracketCode { programmes.choose(bracket: bracket, forTeaching: code) }
                          })
        }
    }

    /// The plan teaching's code, which brackets are stored under.
    private var bracketCode: String? { course.teachingCode ?? pick?.module.code }

    @ViewBuilder
    private var programmeSection: some View {
        if !session.useMockData {
            Section {
                if let programme = programmes.programme {
                    LabeledContent("Corso di studi", value: programme.degreeLabel)
                    LabeledContent("Piano", value: programme.planLabel)
                    if !programme.isConfirmed {
                        Button("È il mio corso di studi") { programmes.confirm() }
                    }
                    Button("Cambia corso di studi") { changingProgramme = true }
                } else if programmes.isLocating {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Button("Scegli il tuo corso di studi") { changingProgramme = true }
                }
            } footer: {
                if programmes.programme?.isConfirmed == false {
                    Text("Dedotto dal nome del tuo corso di studi: controlla che corso e piano siano i tuoi.")
                } else if programmes.programme == nil {
                    Text("Con corso di studi e piano la scheda è quella del tuo piano, non una scelta per nome.")
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        pick = await programmes.pick(teachingCode: course.teachingCode, name: course.name, yearCode: course.academicYearStart)
        syllabus = nil
        if let id = pick?.module.syllabusID { syllabus = await manifesti.syllabus(for: id) }
    }
}

private extension Array where Element == String {
    var nonEmptyJoined: String? { isEmpty ? nil : joined(separator: ", ") }
}

// MARK: - Previews

#Preview("Scheda insegnamento") {
    SyllabusView(classID: "889303", title: "Analisi numerica").previewInNavigation()
}

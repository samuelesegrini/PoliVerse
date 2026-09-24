import SwiftUI

/// The syllabus: how the exam works, the language, the teachers, the hours,
/// the prose sections and the books.
///
/// A different service again — `schedaincarico` — reached with the `c_classe`
/// the manifesto hides behind an icon. Public, and reachable directly: the
/// catalogue routes it through `aunicalogin`, but that only redirects to the
/// same page with two throwaway tokens, so the app skips the round trip.
struct SyllabusView: View {
    /// The `c_classe` the scheda is fetched by.
    let classID: String
    /// The teaching's name, for the bar.
    let title: String

    /// The shared ``ManifestiModel``, from the environment.
    @Environment(ManifestiModel.self) private var manifesti
    @State private var syllabus: Syllabus?
    @State private var loading = true

    /// The view's content.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let syllabus, !syllabus.isEmpty {
                    SyllabusSections(syllabus: syllabus)
                } else {
                    // Said plainly: many teachings simply have no published
                    // scheda, which is not the same as a failure.
                    ContentUnavailableView("Nessuna scheda", systemImage: "book.closed",
                                           description: Text("Il Politecnico non pubblica una scheda per questo modulo."))
                }
            }
            .padding()
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
/// prose and the books. Laid out as cards, for a scrolling page.
struct SyllabusSections: View {
    /// The scheda to draw.
    let syllabus: Syllabus
    /// The colour the cards' icons are drawn in.
    var tint: Color = Theme.brand

    /// Whether the lecturer's own description of the exam is shown in full.
    @State private var notesExpanded = false

    /// The scheda's numbers as tiles: credits, hours in class, hours of independent study.
    /// Figures the page does not state are left out.
    private var facts: [(value: String, label: String)] {
        [
            syllabus.credits.map { ($0.formatted(.number), String(localized: "CFU")) },
            syllabus.assistedMinutes.map { ("\($0 / 60)", String(localized: "ore in aula")) },
            syllabus.selfStudyMinutes.map { ("\($0 / 60)", String(localized: "ore di studio")) },
        ].compactMap { $0 }
    }

    /// The prose sections, less the assessment one — which is drawn above, beside the
    /// structured assessment rows.
    private var proseSections: [(title: String, body: String)] {
        syllabus.sections.filter { !$0.title.localizedCaseInsensitiveContains("valutazione") }
    }

    /// The view's content.
    var body: some View {
        if !facts.isEmpty { FactTiles(facts: facts, tint: tint) }

        if !syllabus.assessment.isEmpty || syllabus.assessmentNotes != nil {
            CardSection("Esame", icon: "pencil.and.list.clipboard", tint: tint) {
                ForEach(Array(syllabus.assessment.enumerated()), id: \.offset) { index, item in
                    if index > 0 { CardDivider(inset: 48) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(tint).frame(width: 22)
                        Text(item).font(.subheadline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                switch PartialExams.policy(assessment: syllabus.assessment, notes: syllabus.assessmentNotes) {
                case .offered:
                    CardDivider(inset: 48)
                    Label("Prove in itinere previste", systemImage: "square.split.2x1")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.green)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                case .none, .unknown:
                    EmptyView()
                }
                if let notes = syllabus.assessmentNotes {
                    CardDivider()
                    CardBlock {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Come lo descrive il docente")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(notes)
                                .font(.subheadline)
                                .lineLimit(notesExpanded ? nil : 5)
                                .textSelection(.enabled)
                            Button(notesExpanded ? "Mostra meno" : "Leggi tutto") {
                                withAnimation(.snappy) { notesExpanded.toggle() }
                            }
                            .font(.caption.weight(.semibold))
                            .tint(tint)
                        }
                    }
                }
            }
        }

        if !syllabus.teachers.isEmpty || syllabus.teachingType != nil || syllabus.language != nil
            || !syllabus.englishSupport.isEmpty {
            CardSection("Insegnamento", icon: "person.2.fill", tint: tint) {
                ForEach(Array(syllabus.teachers.enumerated()), id: \.element.id) { index, teacher in
                    if index > 0 { CardDivider(inset: 60) }
                    HStack(spacing: 12) {
                        InitialsAvatar(name: teacher.name, tint: tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(teacher.name).font(.subheadline.weight(.medium))
                            Text(index == 0 ? String(localized: "Titolare") : String(localized: "Co-titolare"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                if let type = syllabus.teachingType {
                    if !syllabus.teachers.isEmpty { CardDivider() }
                    CardRow(String(localized: "Tipo"), value: type, icon: "square.stack", tint: tint)
                }
                if let language = syllabus.language {
                    CardDivider()
                    CardRow(String(localized: "Lingua"), value: language.label, icon: "globe", tint: tint)
                }
                ForEach(syllabus.englishSupport, id: \.self) { support in
                    CardDivider(inset: 48)
                    Label(support.label, systemImage: "checkmark")
                        .font(.subheadline)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
        }

        if !syllabus.teachingForms.isEmpty {
            CardSection("Impegno", icon: "clock.fill", footer: "Ore indicate dalla scheda del Politecnico.", tint: tint) {
                let total = max(syllabus.teachingForms.reduce(0) { $0 + $1.minutes }, 1)
                ForEach(Array(syllabus.teachingForms.enumerated()), id: \.offset) { index, form in
                    if index > 0 { CardDivider() }
                    CardBlock {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(SyllabusSections.formName(form.name)).font(.subheadline)
                                Spacer()
                                Text(SyllabusSections.hours(form.minutes))
                                    .font(.subheadline.weight(.medium)).monospacedDigit()
                            }
                            ProgressView(value: Double(form.minutes), total: Double(total)).tint(tint)
                        }
                    }
                }
            }
        }

        ForEach(proseSections, id: \.title) { section in
            ProseCard(title: section.title, text: section.body, tint: tint)
        }

        if !syllabus.books.isEmpty {
            CardSection("Bibliografia", icon: "books.vertical.fill", tint: tint) {
                ForEach(Array(syllabus.books.enumerated()), id: \.element.id) { index, book in
                    if index > 0 { CardDivider() }
                    CardBlock {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(book.title).font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(book.isRequired ? String(localized: "Obbligatorio") : String(localized: "Facoltativo"))
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background((book.isRequired ? tint : Color.secondary).opacity(0.15), in: .capsule)
                                    .foregroundStyle(book.isRequired ? tint : .secondary)
                            }
                            if let authors = book.authors { Text(authors).font(.caption) }
                            if let details = book.details {
                                Text(details).font(.caption).foregroundStyle(.secondary)
                            }
                            if let url = book.url {
                                Link(destination: url) {
                                    Label("Apri il link", systemImage: "arrow.up.right.square")
                                }
                                .font(.caption.weight(.medium))
                                .tint(tint)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }

        if let software = syllabus.software {
            CardSection("Software", icon: "laptopcomputer", tint: tint) {
                CardBlock { Text(software).font(.subheadline) }
            }
        }

        if syllabus.brackets.count > 1 {
            CardSection("Scaglioni per corso di studi", icon: "person.3.fill",
                        footer: "Dal primo cognome incluso al secondo escluso.", tint: tint) {
                ForEach(Array(syllabus.brackets.enumerated()), id: \.offset) { index, bracket in
                    if index > 0 { CardDivider() }
                    CardRow(label: bracket.degreeCourse) {
                        Text([bracket.from, bracket.to].compactMap { $0 }.joined(separator: " – ")).monospaced()
                    }
                }
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

    /// Minutes as hours, with the remainder where there is one.
    ///
    /// - Parameter minutes: The duration.
    /// - Returns: The text.
    static func hours(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
    }
}

/// A long prose section, folded to a few lines until asked for.
private struct ProseCard: View {
    /// The section's heading.
    let title: String
    /// The section's prose.
    let text: String
    /// The colour the card's icon is drawn in.
    let tint: Color
    /// Whether the prose is shown in full rather than folded to a few lines.
    @State private var expanded = false

    /// The view's content.
    var body: some View {
        CardSection(verbatim: title, tint: tint) {
            CardBlock {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text)
                        .font(.subheadline)
                        .lineLimit(expanded ? nil : 6)
                        .textSelection(.enabled)
                    if text.count > 320 {
                        Button(expanded ? "Mostra meno" : "Leggi tutto") {
                            withAnimation(.snappy) { expanded.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                        .tint(tint)
                    }
                }
            }
        }
    }
}

/// The scheda of one of the student's own courses, found from its code.
struct CourseSyllabusView: View {
    /// The course whose scheda is being shown.
    let course: Course

    /// The shared ``ManifestiModel``, from the environment.
    @Environment(ManifestiModel.self) private var manifesti
    /// The shared ``StudyProgrammeModel``, from the environment.
    @Environment(StudyProgrammeModel.self) private var programmes
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    @State private var pick: SyllabusPicker.Pick?
    @State private var syllabus: Syllabus?
    @State private var loading = true
    @State private var changingProgramme = false
    @State private var editingCareer: CareerChoice?
    @State private var choosingBracket = false
    @State private var linking = false

    /// The course's own accent.
    private var tint: Color { Theme.accent(for: course) }

    /// The look in use, which the page's materials and typeface come from.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The scheda as a pile: the programme in front, then the exam, the books,
    /// the hours and the teachers, with whose scheda it is under the title.
    private var hero: some View {
        let ramp = CourseRamp(course: course, style: style, scheme: scheme)
        let symbols = ["book.closed", "pencil.and.list.clipboard", "books.vertical", "clock", "person.2"]
        let summary: Text? = if loading {
            nil
        } else if syllabus?.isEmpty == false {
            pick?.matchesDegree == true ? Text("Dalla scheda del tuo piano di studi") : Text("Dal Manifesto degli studi")
        } else {
            Text("Scheda non trovata")
        }
        return CoursePageHero(
            tiles: zip(symbols, ramp.colours(symbols.count)).map { HeroTile(id: $0, symbol: $0, colour: $1) },
            placeholder: HeroTile(id: "empty", symbol: "book.closed", colour: ramp.main),
            title: Text(course.name),
            summary: summary,
            badge: pick?.matchesDegree == true ? HeroBadge(symbol: "checkmark", tint: .green) : nil,
            mode: ramp.mode)
    }

    /// The view's content.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let syllabus, !syllabus.isEmpty {
                    if let pick { pickSection(pick) }
                    if let pick, pick.isIntegrated { modulesSection(pick) }
                    SyllabusSections(syllabus: syllabus, tint: tint)
                } else {
                    // The picture above already says it was not found: here,
                    // only why, and what to do about it.
                    VStack(spacing: 12) {
                        Text(programmes.programme == nil && course.teachingCode == nil
                            ? "Questo corso non ha un codice d'insegnamento: scegli il tuo corso di studi per trovarlo nel tuo piano."
                            : "Non trovo la scheda di questo insegnamento nel Manifesto degli studi.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        if programmes.programme != nil {
                            Button("Collega a un insegnamento del piano") { linking = true }
                                .buttonStyle(.glassProminent)
                                .tint(tint)
                        }
                    }
                }
                programmeSection
            }
            .padding(.horizontal, 20).padding(.vertical)
            .padding(.bottom, 20)
        }
        .navigationTitle("Programma")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: programmes.programme) { await load() }
        .sheet(isPresented: $changingProgramme) { StudyProgrammeSheet() }
        .sheet(item: $editingCareer) { choice in StudyProgrammeSheet(career: choice.matricola) }
        .sheet(isPresented: $linking) { PlanLinkSheet(course: course) }
        .sheet(isPresented: $choosingBracket) {
            BracketPicker(title: course.name, surname: session.student?.lastName ?? "",
                          chosen: bracketCode.flatMap { programmes.programme?.bracket(for: $0) },
                          load: { await programmes.brackets(TeachingRef(course))?.1 ?? [] },
                          onChoose: { bracket in
                              if let code = bracketCode { programmes.choose(bracket: bracket, forTeaching: code) }
                          })
        }
    }

    /// The plan teaching's code, which brackets are stored under.
    private var bracketCode: String? { course.teachingCode ?? pick?.module.code }

    /// Whose scheda this is: the degree course it was found under, the bracket, and a way to
    /// correct either.
    ///
    /// - Parameter pick: The scheda that was chosen.
    /// - Returns: The section.
    private func pickSection(_ pick: SyllabusPicker.Pick) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if let teachers = pick.teachers.nonEmptyJoined {
                    CardRow(pick.teachers.count > 1 ? String(localized: "Docenti") : String(localized: "Docente"),
                            value: teachers, icon: "person.fill", tint: tint)
                }
                if let from = pick.module.scaglioneFrom, let to = pick.module.scaglioneTo, to != "ZZZZ" || from != "A" {
                    CardDivider(inset: 48)
                    CardRow(String(localized: "Scaglione"), value: "\(from) – \(to)", icon: "textformat.abc", tint: tint)
                }
                if let code = bracketCode, programmes.programme?.brackets[code] == nil,
                   programmes.programme?.inferredBrackets[code] != nil {
                    CardDivider(inset: 48)
                    Label("Scaglione dei docenti della tua pagina WeBeep", systemImage: "books.vertical")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                if programmes.programme != nil {
                    CardDivider()
                    HStack(spacing: 8) {
                        Button("Altro scaglione") { choosingBracket = true }
                        Button("Collega altro insegnamento") { linking = true }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .tint(tint)
                    .padding(12)
                }
            }
            .lookCard()

            // Which row was chosen: from the plan when there is one, a guess
            // otherwise — say which.
            Label(pick.matchesDegree
                  ? "Scheda del tuo piano di studi, nello scaglione del tuo cognome o in quello che hai scelto."
                  : "Il tuo corso di studi non risulta tra quelli che offrono questo insegnamento: questa è la scheda del primo che lo offre. Controlla che sia la tua.",
                  systemImage: pick.matchesDegree ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(pick.matchesDegree ? Color.secondary : .orange)
                .padding(.horizontal, 4)
        }
    }

    /// The modules of an integrated course, listed rather than opened — the Politecnico
    /// publishes one scheda for the whole course.
    ///
    /// - Parameter pick: The scheda that was chosen.
    /// - Returns: The section.
    private func modulesSection(_ pick: SyllabusPicker.Pick) -> some View {
        CardSection("Moduli", icon: "square.stack.3d.up.fill",
                    footer: "Corso integrato: il Politecnico pubblica una sola scheda per tutti i moduli, qui sotto.",
                    tint: tint) {
            ForEach(Array(pick.parts.enumerated()), id: \.offset) { index, part in
                if index > 0 { CardDivider() }
                CardBlock {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.name.capitalized).font(.subheadline.weight(.medium))
                        Text([part.code,
                              part.credits.flatMap { $0 > 0 ? String(localized: "\($0.formatted()) CFU") : nil },
                              part.teachers.map(\.name).nonEmptyJoined].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The degree course and plan the scheda was read against, with a way to change them.
    @ViewBuilder
    private var programmeSection: some View {
        if !session.useMockData {
            CardSection("Il tuo corso di studi", icon: "graduationcap.fill", tint: tint) {
                if let programme = programmes.programme {
                    CardRow(String(localized: "Corso di studi"), value: programme.degreeLabel)
                    CardDivider()
                    CardRow(String(localized: "Piano"), value: programme.planLabel)
                    if programme.needsReview {
                        CardDivider()
                        Label("Il tuo libretto non corrisponde più a questo piano, o il piano non c'è più quest'anno.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    CardDivider()
                    HStack(spacing: 8) {
                        if !programme.isConfirmed {
                            Button("È il mio corso di studi") { programmes.confirm() }
                                .buttonStyle(.glassProminent)
                        }
                        Button("Cambia corso di studi") { changingProgramme = true }
                            .buttonStyle(.glass)
                    }
                    .controlSize(.small)
                    .tint(tint)
                    .padding(12)
                } else if programmes.isLocating {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else {
                    Button("Scegli il tuo corso di studi") { changingProgramme = true }
                        .padding(14)
                        .tint(tint)
                }
                let rows = programmes.careerRows
                if rows.count > 1 {
                    ForEach(rows) { row in
                        CardDivider()
                        Button { editingCareer = CareerChoice(matricola: row.matricola) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.matricola == session.student?.matricola
                                         ? String(localized: "Matricola \(row.matricola) · in uso")
                                         : String(localized: "Matricola \(row.matricola)"))
                                        .font(.subheadline)
                                    Text(row.programme.map { "\($0.degreeLabel) · \($0.planLabel)" }
                                         ?? String(localized: "Corso di studi non scelto"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let note = programmeNote {
                Text(note).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.top, -12)
            }
        }
    }

    /// A line saying why the scheda may not be the student's own: an unconfirmed programme, or
    /// a row found under another degree course. `nil` when neither applies.
    private var programmeNote: LocalizedStringKey? {
        if programmes.careerRows.count > 1 {
            return "Ogni carriera ha il suo corso di studi: i corsi dell'altra carriera sono letti dal piano scelto per lei."
        } else if programmes.programme?.isConfirmed == false {
            return "Dedotto dal nome del tuo corso di studi: controlla che corso e piano siano i tuoi."
        } else if programmes.programme == nil {
            return "Con corso di studi e piano la scheda è quella del tuo piano, non una scelta per nome."
        }
        return nil
    }

    /// Finds the scheda for this course and fetches it, if a module with one was found.
    private func load() async {
        loading = true
        defer { loading = false }
        pick = await programmes.pick(TeachingRef(course))
        syllabus = nil
        if let id = pick?.module.syllabusID { syllabus = await manifesti.syllabus(for: id) }
    }
}

/// `sheet(item:)` identity for the career whose programme is being chosen.
private struct CareerChoice: Identifiable {
    /// The enrolment whose programme is being chosen.
    let matricola: String
    /// ``matricola``.
    var id: String { matricola }
}

/// Links a course to a teaching of the plan by hand, for the few that code
/// and name cannot place.
private struct PlanLinkSheet: View {
    /// The course being linked.
    let course: Course
    /// The shared ``StudyProgrammeModel``, from the environment.
    @Environment(StudyProgrammeModel.self) private var programmes
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss
    @State private var plan: [PlanTeaching]?

    /// The view's content.
    var body: some View {
        NavigationStack {
            List {
                if let plan {
                    if programmes.programme?.links[course.id] != nil {
                        Button("Rimuovi il collegamento", role: .destructive) {
                            programmes.link(courseID: course.id, to: nil)
                            dismiss()
                        }
                    }
                    ForEach(Array(Set(plan.map { $0.yearOfCourse ?? "" })).sorted(), id: \.self) { year in
                        Section(year.isEmpty ? String(localized: "Insegnamenti") : String(localized: "\(year)° anno")) {
                            ForEach(plan.filter { ($0.yearOfCourse ?? "") == year }) { row in
                                Button {
                                    programmes.link(courseID: course.id, to: row.teaching.code)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.teaching.name).font(.subheadline)
                                            Text(row.teaching.code).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if programmes.programme?.links[course.id] == row.teaching.code {
                                            Image(systemName: "checkmark").foregroundStyle(Theme.brand)
                                        }
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if plan.isEmpty {
                        Text("Il tuo piano non ha insegnamenti nell'anno di questo corso.").foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(course.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi", systemImage: "xmark") { dismiss() } } }
            .task { plan = await programmes.plan(forYear: course.academicYearStart) }
        }
    }
}

/// Joining a list of strings for display.
private extension Array where Element == String {
    /// The elements joined by commas, or `nil` when there are none.
    var nonEmptyJoined: String? { isEmpty ? nil : joined(separator: ", ") }
}

// MARK: - Previews

#Preview("Scheda insegnamento") {
    SyllabusView(classID: "889303", title: "Analisi numerica").previewInNavigation()
}

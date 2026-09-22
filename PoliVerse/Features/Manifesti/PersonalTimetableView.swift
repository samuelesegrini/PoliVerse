import SwiftUI

/// The personalised timetable, entirely in the app.
///
/// For the weeks before the study plan becomes the official agenda — or when
/// lessons start before the plan can be submitted. The student names
/// themselves, picks teachings, and the app drives the Politecnico's cart and
/// reads the result back into a week it keeps on the phone. The manifesto's
/// own pages are never shown.
struct PersonalTimetableView: View {
    /// The shared ``PersonalTimetableModel``, from the environment.
    @Environment(PersonalTimetableModel.self) private var personal
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// Whether the builder sheet is up.
    /// Which semester's week is shown.
    @State private var building = false
    @State private var semester = 1
    @State private var confirmingDelete = false
    @State private var confirmingExport = false
    @State private var exportOutcome: CalendarExporter.Outcome?

    /// The view's content.
    var body: some View {
        Group {
            if let timetable = personal.timetable {
                week(timetable)
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        PageHero(symbol: "calendar.badge.plus", title: Text("Orario personalizzato"),
                                 summary: Text("Scegli gli insegnamenti che segui e l'app ne ricava l'orario settimanale, con aule e indirizzi."))
                        Button { building = true } label: {
                            Label("Crea l'orario", systemImage: "plus").padding(.horizontal, 8)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .lookList()
        .navigationTitle("Orario personalizzato")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if personal.timetable != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Opzioni", systemImage: "ellipsis.circle") {
                        Button("Modifica insegnamenti", systemImage: "pencil") { building = true }
                        Button(CalendarExporter.canSyncQuietly ? "Aggiorna nel Calendario" : "Aggiungi al Calendario",
                               systemImage: "calendar.badge.plus") { confirmingExport = true }
                        Button("Elimina orario", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
        }
        .sheet(isPresented: $building) {
            PersonalTimetableBuilder()
        }
        .confirmationDialog("Mettere le lezioni nel Calendario?", isPresented: $confirmingExport, titleVisibility: .visible) {
            Button("Sincronizza") {
                guard let timetable = personal.timetable else { return }
                Task { exportOutcome = await CalendarExporter.sync(CalendarExport.drafts(for: timetable)) }
            }
        } message: {
            Text("Le lezioni vanno in un calendario \"Orario personalizzato\", come eventi settimanali fino alla fine delle lezioni. Si aggiorna quando l'orario viene ricalcolato e sparisce se lo archivi o lo elimini.")
        }
        .alert(exportTitle, isPresented: Binding(get: { exportOutcome != nil }, set: { if !$0 { exportOutcome = nil } })) {
            Button("OK") { exportOutcome = nil }
        } message: {
            Text(exportMessage)
        }
        .confirmationDialog("Eliminare l'orario personalizzato?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { personal.delete() }
        }
        .task {
            // The agenda is what decides when this timetable is no longer needed.
            await agenda.load(around: .now)
            if let timetable = personal.timetable {
                let semesters = Set(timetable.visibleEntries.compactMap(\.semester))
                if !semesters.contains(semester), let first = semesters.min() { semester = first }
            }
        }
    }

    /// The title of the alert reporting an export's outcome.
    private var exportTitle: String {
        if case .synced = exportOutcome { return String(localized: "Calendario aggiornato") }
        return String(localized: "Calendario non aggiornato")
    }

    /// The body of that alert: how many events were written, or why none were.
    private var exportMessage: String {
        switch exportOutcome {
        case .synced(let count): String(localized: "\(count) eventi settimanali nel calendario «Orario personalizzato».")
        case .denied: String(localized: "Consenti a PoliVerse l'accesso completo in Impostazioni › Privacy › Calendari.")
        case .failed(let message): message
        case nil: ""
        }
    }

    // MARK: - Week

    /// Whether the official agenda has taken over each teaching, by teaching code.
    ///
    /// - Parameter timetable: The timetable to judge.
    /// - Returns: One status per teaching.
    private func statuses(_ timetable: PersonalTimetable) -> [String: TimetableHandover.Status] {
        Dictionary(uniqueKeysWithValues: timetable.entries.map {
            ($0.code, TimetableHandover.status(of: $0, agenda: agenda.officialEvents))
        })
    }

    /// The chosen semester's week: one card per weekday, with its slots in time order.
    ///
    /// - Parameter timetable: The timetable to draw.
    /// - Returns: The week.
    @ViewBuilder
    private func week(_ timetable: PersonalTimetable) -> some View {
        let statuses = statuses(timetable)
        let visible = timetable.visibleEntries
        let confirmed = visible.filter { statuses[$0.code] == .confirmed }.count
        let clashes = timetable.clashes.filter { $0.allSatisfy { $0.semester == nil || $0.semester == semester } }

        List {
            Section {
                PageHero(symbol: "calendar.badge.plus", title: Text("Orario personalizzato"), summary: Text("\(confirmed) insegnamenti confermati"))
                    .listHeader()
            }
            if timetable.retiredAt != nil {
                Section {
                    Label("Archiviato: ora fa fede l'agenda ufficiale.", systemImage: "archivebox")
                    Button("Torna a usarlo") { personal.retire(false) }
                }
                .lookRow()
            } else if TimetableHandover.suggestsRetiring(confirmed: confirmed, of: visible.count) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("L'orario ufficiale è arrivato", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("L'agenda del Politecnico ha già \(confirmed) insegnamenti su \(visible.count) di questo orario. Puoi archiviarlo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Archivia l'orario personalizzato") { personal.retire(true) }
                            .buttonStyle(.bordered)
                    }
                }
                .lookRow()
            }

            let semesters = Set(timetable.entries.compactMap(\.semester)).sorted()
            if semesters.count > 1 {
                Section {
                    Picker("Semestre", selection: $semester) {
                        ForEach(semesters, id: \.self) { Text("\($0)° semestre").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .lookRow()
            }

            if !clashes.isEmpty {
                Section {
                    ForEach(clashes.indices, id: \.self) { index in
                        Label(clashes[index].map(\.title).joined(separator: " · "),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Sovrapposizioni")
                }
                .lookRow()
            }

            ForEach(2...7, id: \.self) { weekday in
                let slots = visible
                    .filter { $0.semester == nil || $0.semester == semester }
                    .flatMap { entry in entry.slots.filter { $0.weekday == weekday }.map { (entry, $0) } }
                    .sorted { $0.1.startMinutes < $1.1.startMinutes }
                if !slots.isEmpty {
                    Section(weekdayName(weekday)) {
                        ForEach(slots, id: \.1) { entry, slot in
                            SlotRow(entry: entry, slot: slot, status: statuses[entry.code] ?? .personalOnly)
                        }
                    }
                    .lookRow()
                }
            }

            Section {
                ForEach(timetable.entries) { entry in
                    Toggle(isOn: Binding(
                        get: { !timetable.hiddenCodes.contains(entry.code) },
                        set: { personal.setHidden(!$0, code: entry.code) })
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline)
                            Text(statuses[entry.code] == .confirmed
                                 ? String(localized: "Già nell'agenda ufficiale")
                                 : String(localized: "Solo in questo orario"))
                                .font(.caption)
                                .foregroundStyle(statuses[entry.code] == .confirmed ? .green : .secondary)
                        }
                    }
                }
            } header: {
                Text("Insegnamenti")
            } footer: {
                Text("Nascondi un insegnamento quando l'agenda ufficiale lo mostra già, o se lo hai aggiunto solo per curiosità. Calcolato il \(timetable.builtAt.formatted(.dateTime.day().month(.wide).hour().minute().locale(locale))) per \(timetable.name). Le aule possono cambiare nelle prime settimane: ricalcolalo da Modifica.")
            }
            .lookRow()
        }
    }

    /// A weekday's name.
    ///
    /// - Parameter weekday: The weekday in `Calendar` numbering.
    /// - Returns: The name, in the reader's language.
    private func weekdayName(_ weekday: Int) -> String {
        var calendar = PoliMiDate.romeCalendar
        calendar.locale = locale
        return calendar.standaloneWeekdaySymbols[weekday - 1].capitalized(with: locale)
    }
}

/// One weekly slot: its time, its teaching, its room and its address.
private struct SlotRow: View {
    /// The teaching this slot belongs to.
    let entry: PersonalTimetable.Entry
    /// The slot being drawn.
    let slot: PersonalTimetable.Slot
    /// Whether the official agenda now carries this teaching, which the row marks.
    let status: TimetableHandover.Status

    /// The view's content.
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.clock(slot.startMinutes)).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(Self.clock(slot.endMinutes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 48, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.subheadline.weight(.medium))
                if let room = slot.room {
                    Label(room, systemImage: "mappin.and.ellipse").font(.caption)
                }
                if let address = slot.address {
                    Text(address).font(.caption2).foregroundStyle(.secondary)
                }
                if status == .confirmed {
                    Label("Nell'agenda ufficiale", systemImage: "checkmark.seal")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Minutes from midnight as `HH:mm`.
    ///
    /// - Parameter minutes: Minutes from midnight.
    /// - Returns: The time.
    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

// MARK: - Builder

/// Name, teachings, result: the manifesto's cart flow as three native steps.
private struct PersonalTimetableBuilder: View {
    /// The shared ``PersonalTimetableModel``, from the environment.
    @Environment(PersonalTimetableModel.self) private var personal
    /// The shared ``ManifestiModel``, from the environment.
    @Environment(ManifestiModel.self) private var manifesti
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``CourseModel``, from the environment.
    @Environment(CourseModel.self) private var courses
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss
    @AppStorage("manifestoSurname") private var surname = ""
    @AppStorage("personalTimetableFirstName") private var storedFirstName = ""
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career

    /// The builder's four steps: the student's name, the degree course, the teachings, and the
    /// build itself.
    enum Step { case name, course, teachings, build }
    /// Which step the builder is on.
    /// The surname, asked for separately so a compound one is never split wrongly.
    @State private var step: Step = .name
    @State private var lastName = ""
    @State private var firstName = ""
    @State private var page: CataloguePage?
    /// The shared ``StudyProgrammeModel``, from the environment.
    @Environment(StudyProgrammeModel.self) private var programmes
    @State private var yearOfCourse: String?
    @State private var bracketTeaching: ManifestoTeaching?

    /// "Cognome Nome", the single field the service takes. Asked for in two
    /// so a compound surname — "De Luca" — is never split in the wrong place.
    private var name: String {
        [lastName, firstName].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The degree course the career names, used to open the cascade in the right place.
    private var myDegree: String? { career.planHeader?.course }

    /// The view's content.
    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .name: nameStep
                case .course: courseStep
                case .teachings: teachingsStep
                case .build: buildStep
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }.disabled(personal.isBuilding)
                }
            }
            .interactiveDismissDisabled(personal.isBuilding)
        }
        .task {
            personal.resetProgress()
            await career.load()
            if lastName.isEmpty {
                lastName = !surname.isEmpty ? surname : session.student?.lastName ?? ""
                firstName = !storedFirstName.isEmpty ? storedFirstName : session.student?.firstName ?? ""
            }
        }
    }

    // Step 1

    /// The first step: the surname and forename the service picks brackets from.
    private var nameStep: some View {
        Form {
            Section {
                TextField("Cognome", text: $lastName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.familyName)
                TextField("Nome", text: $firstName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.givenName)
            } header: {
                Text("Chi sei")
            } footer: {
                Text("Il Politecnico usa cognome **e** nome per scegliere il tuo scaglione, cioè docente e orario. Con il solo cognome può sbagliare.")
            }
            .lookRow()
        }
        .navigationTitle("Orario personalizzato")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Avanti") {
                    surname = lastName.trimmingCharacters(in: .whitespaces)
                    storedFirstName = firstName.trimmingCharacters(in: .whitespaces)
                    step = .course
                    Task { await personal.prepare(name: name) }
                }
                .disabled(lastName.trimmingCharacters(in: .whitespaces).isEmpty
                          || firstName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // Step 2: where in the manifesto

    /// The second step: the degree course and plan, through ``CatalogueCascade``.
    private var courseStep: some View {
        Form {
            CatalogueCascade(page: Binding(get: { page }, set: { found in
                page = found
                personal.catalogue = found?.selection
                yearOfCourse = nil
            }), initial: personal.catalogue ?? programmes.programme?.selection)
        }
        .navigationTitle("Corso di studi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Indietro") { step = .name }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Avanti") {
                    // Picked here with nothing confirmed yet: this is the
                    // student's own programme, so the course pages use it too.
                    if let page, programmes.programme?.isConfirmed != true {
                        programmes.set(page, confirmed: true)
                    }
                    step = .teachings
                }
                .disabled(page?.teachings.isEmpty ?? true)
            }
        }
        .task { await programmes.prepare() }
    }

    // Step 3: the plan's teachings

    /// The years of course the chosen plan lists, in order.
    private var yearsOfCourse: [String] {
        Array(Set(page?.teachings.compactMap(\.yearOfCourse) ?? [])).sorted()
    }

    /// The third step: the plan's teachings by year of course, with the chosen ones counted
    /// against ``PersonalTimetableModel/capacity``.
    private var teachingsStep: some View {
        let rows = (page?.teachings ?? []).filter { yearOfCourse == nil || $0.yearOfCourse == yearOfCourse }
        let listed = Set((page?.teachings ?? []).map(\.teaching.code))
        let elsewhere = personal.selection.filter { !listed.contains($0.code) }
        return List {
            if yearsOfCourse.count > 1 {
                Section {
                    Picker("Anno di corso", selection: $yearOfCourse) {
                        Text("Tutti").tag(String?.none)
                        ForEach(yearsOfCourse, id: \.self) { Text("\($0)° anno").tag(String?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                .lookRow()
            }

            ForEach(Array(Set(rows.map { $0.yearOfCourse ?? "" })).sorted(), id: \.self) { year in
                Section {
                    ForEach(rows.filter { ($0.yearOfCourse ?? "") == year }) { row in
                        teachingRow(row)
                    }
                } header: {
                    Text(year.isEmpty ? String(localized: "Insegnamenti") : String(localized: "\(year)° anno"))
                }
                .lookRow()
            }

            if !elsewhere.isEmpty {
                Section {
                    ForEach(elsewhere) { teaching in
                        HStack {
                            ManifestoRow(teaching: teaching)
                            Spacer()
                            Button("Rimuovi", systemImage: "minus.circle.fill") { personal.toggle(teaching) }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.red)
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Da altri piani")
                }
                .lookRow()
            }
        }
        .sheet(item: $bracketTeaching) { teaching in
            BracketPicker(title: teaching.name, surname: lastName,
                          chosen: personal.bracketChoices[teaching.code],
                          load: { await manifesti.brackets(for: teaching) },
                          onChoose: { personal.choose(bracket: $0, for: teaching) })
        }
        .sheet(item: Binding(get: { personal.pendingSections.map { PendingID(code: $0.teaching.code) } },
                             set: { if $0 == nil, let pending = personal.pendingSections {
                                 personal.choose(nil, for: pending.teaching, link: pending.link) } })) { _ in
            if let pending = personal.pendingSections {
                SectionPicker(teaching: pending.teaching, options: pending.options) { option in
                    personal.choose(option, for: pending.teaching, link: pending.link)
                }
            }
        }
        .navigationTitle("Selezionati \(personal.selection.count)/\(PersonalTimetableModel.capacity)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Indietro") { step = .course }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Calcola") {
                    step = .build
                    Task { await personal.build(name: name, surname: lastName) }
                }
                .disabled(personal.selection.isEmpty)
            }
        }
    }

    /// One teaching of the plan: its name, its credits, and a way to choose another bracket.
    ///
    /// - Parameter row: The plan row to draw.
    /// - Returns: The row.
    private func teachingRow(_ row: PlanTeaching) -> some View {
        let selected = personal.isSelected(row.teaching)
        let details: [String] = [
            row.teaching.code,
            row.teaching.semester.map { String(localized: "\($0)° sem") },
            row.credits.map { String(localized: "\($0.formatted()) CFU") },
            row.group.map { String(localized: "A scelta · \($0)") },
        ].compactMap { $0 }
        return HStack(spacing: 12) {
            Button {
                let adding = !personal.isSelected(row.teaching)
                personal.toggle(row)
                // A bracket already chosen, or read from WeBeep, for this
                // teaching: the timetable follows it without asking again.
                if adding, personal.bracketChoices[row.teaching.code] == nil,
                   let known = programmes.programme?.bracket(for: row.teaching.code),
                   !known.covers(surname: lastName) {
                    personal.choose(bracket: known, for: row.teaching)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.green : Color.secondary)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.teaching.name).font(.subheadline.weight(.medium))
                        Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        if let bracket = personal.bracketChoices[row.teaching.code] {
                            Label(String(localized: "Scaglione \(bracket.label)"), systemImage: "person.2")
                                .font(.caption).foregroundStyle(Theme.brand)
                        }
                        if let section = personal.sectionChoices[row.teaching.code] {
                            Label(section.option.label, systemImage: "person.2")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!selected && personal.selection.count >= PersonalTimetableModel.capacity)

            if selected, !row.hasSections {
                Button("Scaglione", systemImage: "person.2.badge.gearshape") { bracketTeaching = row.teaching }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        }
    }

    // Step 3

    /// The last step: the build's progress, and what the service refused.
    private var buildStep: some View {
        List {
            Section {
                switch personal.progress {
                case .idle, .settingName:
                    ProgressRow(text: String(localized: "Imposto lo scaglione…"))
                case .adding(let done, let total):
                    ProgressView(value: Double(done), total: Double(total)) {
                        Text("Aggiungo gli insegnamenti: \(done) di \(total)")
                    }
                case .reading:
                    ProgressRow(text: String(localized: "Leggo l'orario…"))
                case .finished:
                    Label("Orario pronto", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if let timetable = personal.timetable {
                        Text("\(timetable.entries.count) insegnamenti, \(timetable.entries.reduce(0) { $0 + $1.slots.count }) lezioni a settimana.")
                            .foregroundStyle(.secondary)
                        if timetable.entries.allSatisfy({ $0.slots.isEmpty }) {
                            Text("Il Politecnico non ha ancora pubblicato gli orari di questi insegnamenti. Ricalcola più avanti.")
                                .foregroundStyle(.orange)
                        }
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Button("Riprova") { Task { await personal.build(name: name, surname: lastName) } }
                }
            }
            .lookRow()

            if !personal.refused.isEmpty {
                Section {
                    ForEach(personal.refused, id: \.teaching.id) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.teaching.name).font(.subheadline)
                            Text(item.reason ?? String(localized: "Non aggiunto dal Politecnico."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Non aggiunti")
                }
                .lookRow()
            }
        }
        .navigationTitle("Calcolo dell'orario")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Indietro") { step = .teachings }.disabled(personal.isBuilding)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Fine") { dismiss() }.disabled(personal.progress != .finished)
            }
        }
    }
}

/// `sheet(item:)` identity for the section question on screen, so the next
/// question replaces it instead of the sheet staying shut.
private struct PendingID: Identifiable {
    /// The teaching code the question is about.
    let code: String
    /// ``code``.
    var id: String { code }
}

/// Which section of a teaching offered in sections.
private struct SectionPicker: View {
    /// The teaching whose sections are being chosen between.
    let teaching: ManifestoTeaching
    /// The sections on offer.
    let options: [PersonalTimetableParser.SectionOption]
    /// Records the chosen section.
    let onChoose: (PersonalTimetableParser.SectionOption) -> Void

    /// The view's content.
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options) { option in
                        Button { onChoose(option) } label: {
                            HStack {
                                Text(option.label)
                                Spacer()
                                if option.isPreselected {
                                    Text("Suggerita").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Questo insegnamento è diviso in sezioni: scegli quella che frequenti. Se non scegli, il Politecnico usa quella del tuo scaglione.")
                }
                .lookRow()
            }
            .navigationTitle(teaching.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/// One line of the build's progress, with a spinner beside it.
private struct ProgressRow: View {
    /// What the build is doing.
    let text: String
    /// The view's content.
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
        }
    }
}

// MARK: - Previews

#Preview("Orario personalizzato") {
    PersonalTimetableView().previewInNavigation()
}

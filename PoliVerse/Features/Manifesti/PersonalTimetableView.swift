import SwiftUI

/// The personalised timetable, entirely in the app.
///
/// For the weeks before the study plan becomes the official agenda — or when
/// lessons start before the plan can be submitted. The student names
/// themselves, picks teachings, and the app drives the Politecnico's cart and
/// reads the result back into a week it keeps on the phone. The manifesto's
/// own pages are never shown.
struct PersonalTimetableView: View {
    @Environment(PersonalTimetableService.self) private var personal
    @Environment(AgendaService.self) private var agenda
    @Environment(\.locale) private var locale

    @State private var building = false
    @State private var semester = 1
    @State private var confirmingDelete = false
    @State private var confirmingExport = false
    @State private var exportOutcome: CalendarExporter.Outcome?

    var body: some View {
        Group {
            if let timetable = personal.timetable {
                week(timetable)
            } else {
                ContentUnavailableView {
                    Label("Nessun orario personalizzato", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Scegli gli insegnamenti che segui e l'app ne ricava l'orario settimanale, con aule e indirizzi. Utile finché il piano di studi non arriva nell'agenda.")
                } actions: {
                    Button("Crea l'orario") { building = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Orario personalizzato")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if personal.timetable != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Opzioni", systemImage: "ellipsis.circle") {
                        Button("Modifica insegnamenti", systemImage: "pencil") { building = true }
                        Button("Aggiungi al Calendario", systemImage: "calendar.badge.plus") { confirmingExport = true }
                        Button("Elimina orario", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
        }
        .sheet(isPresented: $building) {
            PersonalTimetableBuilder()
        }
        .confirmationDialog("Aggiungere le lezioni al Calendario?", isPresented: $confirmingExport, titleVisibility: .visible) {
            Button("Aggiungi") {
                guard let timetable = personal.timetable else { return }
                Task { exportOutcome = await CalendarExporter.export(CalendarExport.drafts(for: timetable)) }
            }
        } message: {
            Text("Ogni lezione diventa un evento settimanale fino alla fine delle lezioni. Se le hai già aggiunte, verranno duplicate.")
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

    private var exportTitle: String {
        if case .added = exportOutcome { return String(localized: "Lezioni aggiunte") }
        return String(localized: "Calendario non aggiornato")
    }

    private var exportMessage: String {
        switch exportOutcome {
        case .added(let count): String(localized: "\(count) eventi settimanali nel calendario predefinito.")
        case .denied: String(localized: "Consenti a PoliVerse di aggiungere eventi in Impostazioni › Privacy › Calendari.")
        case .failed(let message): message
        case nil: ""
        }
    }

    // MARK: - Week

    private func statuses(_ timetable: PersonalTimetable) -> [String: TimetableHandover.Status] {
        Dictionary(uniqueKeysWithValues: timetable.entries.map {
            ($0.code, TimetableHandover.status(of: $0, agenda: agenda.officialEvents))
        })
    }

    @ViewBuilder
    private func week(_ timetable: PersonalTimetable) -> some View {
        let statuses = statuses(timetable)
        let visible = timetable.visibleEntries
        let confirmed = visible.filter { statuses[$0.code] == .confirmed }.count
        let clashes = timetable.clashes.filter { $0.allSatisfy { $0.semester == nil || $0.semester == semester } }

        List {
            if timetable.retiredAt != nil {
                Section {
                    Label("Archiviato: ora fa fede l'agenda ufficiale.", systemImage: "archivebox")
                    Button("Torna a usarlo") { personal.retire(false) }
                }
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
            }

            let semesters = Set(timetable.entries.compactMap(\.semester)).sorted()
            if semesters.count > 1 {
                Section {
                    Picker("Semestre", selection: $semester) {
                        ForEach(semesters, id: \.self) { Text("\($0)° semestre").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
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
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        var calendar = PoliMiDate.romeCalendar
        calendar.locale = locale
        return calendar.standaloneWeekdaySymbols[weekday - 1].capitalized(with: locale)
    }
}

private struct SlotRow: View {
    let entry: PersonalTimetable.Entry
    let slot: PersonalTimetable.Slot
    let status: TimetableHandover.Status

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

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

// MARK: - Builder

/// Name, teachings, result: the manifesto's cart flow as three native steps.
private struct PersonalTimetableBuilder: View {
    @Environment(PersonalTimetableService.self) private var personal
    @Environment(ManifestiService.self) private var manifesti
    @Environment(Session.self) private var session
    @Environment(CourseService.self) private var courses
    @Environment(\.dismiss) private var dismiss
    @AppStorage("manifestoSurname") private var surname = ""
    @AppStorage("personalTimetableFirstName") private var storedFirstName = ""
    @Environment(CareerService.self) private var career

    enum Step { case name, teachings, build }
    @State private var step: Step = .name
    @State private var lastName = ""
    @State private var firstName = ""
    @State private var query = ""
    @State private var onlyMyDegree = true

    /// "Cognome Nome", the single field the service takes. Asked for in two
    /// so a compound surname — "De Luca" — is never split in the wrong place.
    private var name: String {
        [lastName, firstName].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var myDegree: String? { career.planHeader?.course }

    var body: some View {
        @Bindable var manifesti = manifesti
        NavigationStack {
            Group {
                switch step {
                case .name: nameStep(year: $manifesti.year)
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

    private func nameStep(year: Binding<AcademicYear>) -> some View {
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
            Section("Anno accademico") {
                Picker("Anno accademico", selection: year) {
                    ForEach(AcademicYear.recent()) { Text($0.label).tag($0) }
                }
            }
        }
        .navigationTitle("Orario personalizzato")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Avanti") {
                    surname = lastName.trimmingCharacters(in: .whitespaces)
                    storedFirstName = firstName.trimmingCharacters(in: .whitespaces)
                    step = .teachings
                    Task { await personal.prepare(name: name) }
                }
                .disabled(lastName.trimmingCharacters(in: .whitespaces).isEmpty
                          || firstName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // Step 2

    private var suggestions: [Course] {
        courses.visibleCourses.filter { course in
            course.teachingCode != nil && !personal.selection.contains { $0.code == course.teachingCode }
        }
    }

    /// The search results, narrowed to the student's degree course when asked
    /// — the same teaching has different times in different courses.
    private var results: [ManifestoTeaching] {
        guard onlyMyDegree, let myDegree else { return manifesti.results }
        return manifesti.results.filter { DegreeCourseMatch.matches($0.degreeCourse, plan: myDegree) }
    }

    private var teachingsStep: some View {
        List {
            Section {
                if personal.selection.isEmpty {
                    Text("Cerca un insegnamento per nome o codice e toccalo per aggiungerlo.")
                        .foregroundStyle(.secondary)
                }
                ForEach(personal.selection) { teaching in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            ManifestoRow(teaching: teaching)
                            if let section = personal.sectionChoices[teaching.code] {
                                Label(section.option.label, systemImage: "person.2")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Rimuovi", systemImage: "minus.circle.fill") { personal.toggle(teaching) }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.red)
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Selezionati \(personal.selection.count)/\(PersonalTimetableService.capacity)")
            } footer: {
                if !personal.selection.isEmpty {
                    Text("Scegli la riga del tuo corso di studi: lo stesso insegnamento può avere orari diversi in corsi diversi.")
                }
            }

            if query.isEmpty, !suggestions.isEmpty {
                Section("Dai tuoi corsi") {
                    ForEach(suggestions.prefix(8)) { course in
                        Button {
                            query = course.teachingCode ?? course.name
                            Task { await manifesti.search(query) }
                        } label: {
                            Label(course.name, systemImage: "magnifyingglass")
                        }
                    }
                }
            }

            if let myDegree {
                Section {
                    Toggle(isOn: $onlyMyDegree) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Solo il mio corso di studi")
                            Text(myDegree).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if manifesti.isSearching {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if !query.isEmpty, !manifesti.results.isEmpty {
                Section {
                    ForEach(results) { teaching in
                        Button { personal.toggle(teaching) } label: {
                            HStack {
                                ManifestoRow(teaching: teaching)
                                Spacer()
                                Image(systemName: personal.isSelected(teaching) ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(personal.isSelected(teaching) ? Color.green : Theme.brand)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!personal.isSelected(teaching)
                                  && personal.selection.count >= PersonalTimetableService.capacity)
                    }
                } header: {
                    Text("Risultati")
                } footer: {
                    if results.isEmpty {
                        Text("Nessun risultato nel tuo corso di studi: disattiva il filtro per vedere gli altri corsi.")
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { personal.pendingSections != nil },
                                    set: { if !$0, let pending = personal.pendingSections {
                                        personal.choose(nil, for: pending.teaching, link: pending.link) } })) {
            if let pending = personal.pendingSections {
                SectionPicker(teaching: pending.teaching, options: pending.options) { option in
                    personal.choose(option, for: pending.teaching, link: pending.link)
                }
            }
        }
        .searchable(text: $query, prompt: "Nome o codice dell'insegnamento")
        .onSubmit(of: .search) { Task { await manifesti.search(query) } }
        .navigationTitle("Insegnamenti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Indietro") { step = .name }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Calcola") {
                    step = .build
                    Task { await personal.build(name: name) }
                }
                .disabled(personal.selection.isEmpty)
            }
        }
    }

    // Step 3

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
                    Button("Riprova") { Task { await personal.build(name: name) } }
                }
            }

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

/// Which section of a teaching offered in sections.
private struct SectionPicker: View {
    let teaching: ManifestoTeaching
    let options: [PersonalTimetableParser.SectionOption]
    let onChoose: (PersonalTimetableParser.SectionOption) -> Void

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
            }
            .navigationTitle(teaching.name)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ProgressRow: View {
    let text: String
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

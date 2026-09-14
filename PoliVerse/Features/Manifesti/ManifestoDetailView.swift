import SwiftUI

/// One teaching, as the manifesto describes it.
///
/// The scaglione is the reason this screen matters: a first-year student's
/// lecturer and timetable depend on which surname bracket they fall in, and no
/// other Politecnico service exposes that. Enter a surname and the bracket
/// that applies is marked.
struct ManifestoDetailView: View {
    let teaching: ManifestoTeaching

    @Environment(ManifestiService.self) private var manifesti
    @AppStorage("manifestoSurname") private var surname = ""

    @State private var detail: ManifestoDetail?
    @State private var loading = true
    @Environment(PersonalTimetableService.self) private var personal

    var body: some View {
        List {
            if loading && detail == nil {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }

            if let detail {
                if let summary = detail.summary {
                    Section("Programma sintetico") {
                        Text(summary).font(.subheadline)
                    }
                }

                if !detail.facts.isEmpty || !detail.languages.isEmpty {
                    Section("Insegnamento") {
                        // First, because it decides the language of the
                        // lectures, the materials and the exam.
                        if !detail.languages.isEmpty {
                            LabeledContent("Lingua di erogazione",
                                           value: detail.languages.map(\.label).joined(separator: ", "))
                        }
                        ForEach(detail.facts, id: \.label) { fact in
                            LabeledContent(fact.label, value: fact.value)
                        }
                    }
                }

                if !detail.context.isEmpty {
                    Section("Contesto") {
                        ForEach(detail.context, id: \.label) { fact in
                            LabeledContent(fact.label, value: fact.value)
                        }
                    }
                }

                if !detail.ssd.isEmpty {
                    Section("Settori scientifico-disciplinari") {
                        ForEach(detail.ssd) { area in
                            LabeledContent {
                                Text(area.credits.map { "\($0, format: .number) CFU" } ?? "—")
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(area.code).font(.subheadline).monospaced()
                                    Text(area.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                modulesSection(detail)

                Section {
                    Button {
                        personal.toggle(teaching)
                    } label: {
                        if personal.isSelected(teaching) {
                            Label("Nel mio orario personalizzato", systemImage: "checkmark.circle.fill")
                        } else {
                            Label("Aggiungi al mio orario", systemImage: "calendar.badge.plus")
                        }
                    }
                    .disabled(!personal.isSelected(teaching)
                              && personal.selection.count >= PersonalTimetableService.capacity)
                } footer: {
                    Text("Viene aggiunto alla selezione dell'orario personalizzato: calcola l'orario da lì. È uno strumento informale del Politecnico e non sostituisce il piano di studi.")
                }
            } else if !loading {
                Section {
                    Text("Il catalogo non ha restituito questa scheda.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(teaching.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await manifesti.detail(for: teaching)
            loading = false
        }
    }

    @ViewBuilder
    private func modulesSection(_ detail: ManifestoDetail) -> some View {
        if !detail.modules.isEmpty {
            Section {
                // Only asked for when it changes something: with a single
                // bracket there is nothing to choose between.
                if detail.modules.contains(where: { $0.scaglioneTo != nil })
                    && detail.modules.count > 1 {
                    TextField("Il tuo cognome", text: $surname)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                ForEach(detail.modules) { module in
                    ModuleRow(module: module, surname: surname)
                }
            } header: {
                Text("Moduli e docenti")
            } footer: {
                if detail.modules.contains(where: { $0.scaglioneTo != nil }) {
                    Text("Lo scaglione è per cognome, dal primo incluso al secondo escluso. Scrivi il tuo cognome per vedere quale ti riguarda.")
                }
            }
        }
    }
}

private struct ModuleRow: View {
    let module: ManifestoModule
    let surname: String

    private var isMine: Bool {
        !surname.isEmpty && module.covers(surname: surname)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(module.name.isEmpty ? module.code : module.name)
                    .font(.subheadline.weight(isMine ? .semibold : .regular))
                    .lineLimit(3)
                Spacer(minLength: 6)
                if isMine {
                    Text("il tuo")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.green.opacity(0.18), in: .capsule)
                        .foregroundStyle(.green)
                }
            }

            if let from = module.scaglioneFrom, let to = module.scaglioneTo {
                Label("\(from) – \(to)", systemImage: "textformat.abc")
                    .font(.caption2)
                    .foregroundStyle(isMine ? Color.green : .secondary)
            }

            ForEach(module.teachers) { teacher in
                Label(teacher.name, systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(module.code).monospaced()
                if let credits = module.credits { Text("\(credits, format: .number) CFU") }
                if let period = module.period { Text(period) }
                if let language = module.language { Text(language.label) }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if let syllabusID = module.syllabusID {
                NavigationLink {
                    SyllabusView(classID: syllabusID, title: module.name)
                } label: {
                    Label("Programma, prerequisiti e bibliografia", systemImage: "text.book.closed")
                        .font(.caption)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

#Preview("Dettaglio insegnamento") {
    ManifestoDetailView(teaching: ManifestoTeaching(
        code: "086214", name: "METODI ANALITICI E NUMERICI",
        courseCode: "352", planCode: "E3N", idItemOfferta: nil, idRiga: nil,
        semester: "2", year: "2026", credits: 10, school: nil, degreeCourse: nil))
        .previewInNavigation()
}

#Preview("Componente · Modulo") {
    List {
        ModuleRow(module: ManifestoModule(
            code: "086213", name: "ANALISI NUMERICA",
            teachers: [ManifestoTeacher(name: "Scotti Anna", kDoc: "151967")],
            credits: 5, period: "2° sem", language: nil,
            scaglioneFrom: "A", scaglioneTo: "M", syllabusID: "889303"),
            surname: "Casati")
        ModuleRow(module: ManifestoModule(
            code: "086212", name: "ANALISI MATEMATICA",
            teachers: [ManifestoTeacher(name: "Cerutti Maria Cristina", kDoc: "1085")],
            credits: 5, period: "2° sem", language: nil,
            scaglioneFrom: "M", scaglioneTo: "ZZZZ", syllabusID: nil),
            surname: "Casati")
    }
    .previewInNavigation()
}

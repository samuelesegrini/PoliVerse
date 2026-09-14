import SwiftUI

/// Anno accademico, sede, scuola, corso di studi, piano: the manifesto's own
/// cascade, as native pickers. Each change asks the service for the page, and
/// the levels below are whatever it settles on.
///
/// Used by the personal timetable and by the study programme, so the two
/// always pick a degree course the same way.
struct CatalogueCascade: View {
    @Binding var page: CataloguePage?
    /// Where to open when there is no page yet.
    let initial: CatalogueSelection?

    @Environment(ManifestiService.self) private var manifesti
    @Environment(CareerService.self) private var career
    @State private var loading = false
    @State private var message: String?

    private static let levels: [(CatalogueField, LocalizedStringKey)] = [
        (.year, "Anno accademico"), (.campus, "Sede"), (.school, "Scuola"),
        (.degree, "Corso di studi"), (.plan, "Piano di studi"),
    ]

    var body: some View {
        Group {
            if let page {
                Section {
                    ForEach(Self.levels, id: \.0) { field, title in
                        if let level = page.level(field) { picker(level, title: title) }
                    }
                } footer: {
                    Text("Come nel Manifesto degli studi: ogni scelta restringe la successiva. Il piano è quello preventivamente approvato (PSPA) che segui.")
                }
            }
            if let message {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    if page == nil { Button("Riprova") { Task { await open() } } }
                }
            }
            if loading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .disabled(loading)
        .task { if page == nil { await open() } }
    }

    @ViewBuilder
    private func picker(_ level: CatalogueLevel, title: LocalizedStringKey) -> some View {
        let binding = Binding(get: { level.selected ?? "" },
                              set: { value in Task { await change(level.field, to: value) } })
        let groups = level.options.reduce(into: [String?]()) { groups, option in
            if !groups.contains(option.group) { groups.append(option.group) }
        }
        if level.options.count == 1 {
            LabeledContent(title, value: level.options[0].label)
        } else {
            Picker(title, selection: binding) {
                ForEach(groups, id: \.self) { group in
                    Section(group ?? "") {
                        ForEach(level.options.filter { $0.group == group }) { Text($0.label).tag($0.value) }
                    }
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    /// Where the student was, else their degree course as the career names
    /// it, else the manifesto as it first shows itself.
    private func open() async {
        loading = true
        defer { loading = false }
        message = nil
        if let initial, let found = await manifesti.cataloguePage(initial) {
            show(found)
            return
        }
        await career.load()
        if let degree = career.planHeader?.course, let located = await manifesti.locateDegree(named: degree) {
            show(located)
            return
        }
        guard let first = await manifesti.cataloguePage(nil) else {
            message = String(localized: "Il Manifesto degli studi non risponde. Riprova tra poco.")
            return
        }
        show(first)
    }

    private func change(_ field: CatalogueField, to value: String) async {
        guard let current = page?.selection, current[field] != value else { return }
        loading = true
        defer { loading = false }
        if let found = await manifesti.cataloguePage(current.setting(field, to: value)) {
            show(found)
        } else {
            // The service answers with an error page when a campus offers
            // nothing that year: say so and keep the last good choice.
            message = String(localized: "Nessun corso di studi con questa scelta. Prova un'altra sede o un altro anno.")
        }
    }

    private func show(_ found: CataloguePage) {
        page = found
        message = found.teachings.isEmpty && found.selection != nil
            ? String(localized: "Questo piano non elenca insegnamenti.") : nil
    }
}

/// Which bracket of a teaching to follow: the one the surname falls in by
/// default, or another lecturer's. Choosing the student's own stores nothing.
struct BracketPicker: View {
    let title: String
    let surname: String
    let chosen: BracketChoice?
    let load: () async -> [BracketChoice]
    let onChoose: (BracketChoice?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var brackets: [BracketChoice]?

    var body: some View {
        NavigationStack {
            List {
                if let brackets {
                    if brackets.isEmpty {
                        Text("Questo insegnamento ha un solo scaglione per tutti.").foregroundStyle(.secondary)
                    }
                    Section {
                        ForEach(brackets, id: \.self) { bracket in
                            let mine = bracket.covers(surname: surname)
                            let selected = chosen.map { $0 == bracket } ?? mine
                            Button {
                                onChoose(mine ? nil : bracket)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bracket.label).font(.subheadline.weight(.medium))
                                        Text(bracket.teachers.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if mine { Text("Il tuo").font(.caption).foregroundStyle(.secondary) }
                                    if selected { Image(systemName: "checkmark").foregroundStyle(Theme.brand) }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        if !brackets.isEmpty {
                            Text("Il tuo scaglione dipende dal cognome. Sceglierne un altro vale solo per questo insegnamento.")
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task { brackets = await load() }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The student's degree course and plan, chosen in the manifesto's cascade.
struct StudyProgrammeSheet: View {
    @Environment(StudyProgrammeService.self) private var programmes
    @Environment(\.dismiss) private var dismiss
    @State private var page: CataloguePage?

    var body: some View {
        NavigationStack {
            Form {
                CatalogueCascade(page: $page, initial: programmes.programme?.selection)
            }
            .navigationTitle("Il tuo corso di studi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        if let page { programmes.set(page, confirmed: true) }
                        dismiss()
                    }
                    .disabled(page?.selection == nil)
                }
            }
        }
    }
}

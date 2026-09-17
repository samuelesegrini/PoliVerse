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
    /// Whether to open on the degree course the career in use names, when
    /// there is nothing to open on — wrong for picking another career's.
    var locatesFromCareer = true

    @Environment(ManifestiModel.self) private var manifesti
    @Environment(CareerModel.self) private var career
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
        if locatesFromCareer {
            await career.load()
            if let degree = career.planHeader?.course,
               let located = await manifesti.locateDegree(named: degree, kind: career.planHeader?.level) {
                show(located)
                return
            }
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
        // Landed on the empty non-differentiated plan: open the first real one.
        if found.selection?.plan == "***", let real = found.level(.plan)?.options.first?.value, real != "***" {
            Task { await change(.plan, to: real) }
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let brackets {
                        if brackets.isEmpty {
                            Text("Questo insegnamento ha un solo scaglione per tutti.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 30)
                        } else {
                            // One glass row per bracket; the chosen one is the
                            // row with the check.
                            GlassEffectContainer(spacing: 10) {
                                VStack(spacing: 10) {
                                    ForEach(brackets, id: \.self) { bracket in
                                        row(bracket)
                                    }
                                }
                            }
                            Text("Il tuo scaglione dipende dal cognome. Sceglierne un altro vale solo per questo insegnamento.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    }
                }
                .padding(20)
            }
            .courseScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task { brackets = await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ bracket: BracketChoice) -> some View {
        let mine = bracket.covers(surname: surname)
        let selected = chosen.map { $0 == bracket } ?? mine
        return Button {
            onChoose(mine ? nil : bracket)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bracket.label).font(.headline)
                        if mine {
                            Text("Il tuo")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.quaternary.opacity(0.6), in: .capsule)
                        }
                    }
                    Text(bracket.teachers.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The degree course and plan of one career, chosen in the manifesto's cascade.
struct StudyProgrammeSheet: View {
    /// Nil for the career in use.
    var career: String? = nil

    @Environment(StudyProgrammeModel.self) private var programmes
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var page: CataloguePage?

    private var target: String? { career ?? session.student?.matricola }

    var body: some View {
        NavigationStack {
            Form {
                if let career {
                    Section {
                        LabeledContent("Matricola", value: career)
                    } footer: {
                        if career != session.student?.matricola {
                            Text("Per una carriera diversa da quella in uso il Politecnico non dice il corso di studi: sceglilo tu. I suoi corsi saranno letti da questo piano.")
                        }
                    }
                }
                CatalogueCascade(page: $page, initial: target.flatMap(programmes.initialSelection(for:)),
                                 locatesFromCareer: career == nil || career == session.student?.matricola)
            }
            .courseScreen()
            .navigationTitle("Corso di studi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", systemImage: "checkmark") {
                        if let page, let target { programmes.set(page, for: target) }
                        dismiss()
                    }
                    .disabled(page?.selection == nil || target == nil)
                }
            }
        }
    }
}

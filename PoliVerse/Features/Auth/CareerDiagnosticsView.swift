#if DEBUG
import SwiftUI
import UIKit

/// What the career services actually send, for finding the degree course
/// and plan codes of a matricola.
///
/// Debug builds only. Values are masked unless shown on purpose, and the copied
/// report follows the same choice: it is meant to be pasted into a bug report
/// without handing over a libretto.
struct CareerDiagnosticsView: View {
    @Environment(Session.self) private var session
    @Environment(ManifestiModel.self) private var manifesti

    private struct Payload: Identifiable {
        let id: String
        let title: String
        var fields: [PayloadInspector.Field] = []
        var error: String?
    }

    private struct ClassCheck: Identifiable {
        var id: String { code + classID }
        let code: String
        let name: String
        let classID: String
        let examLecturer: String?
        let schedaLecturers: [String]?
    }

    @State private var payloads: [Payload] = []
    @State private var checks: [ClassCheck] = []
    @State private var loading = false
    @State private var showValues = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                LabeledContent(String("Matricola"), value: showValues ? (session.student?.matricola ?? "—")
                               : PayloadInspector.mask(session.student?.matricola ?? "—"))
                Toggle(String("Mostra i valori"), isOn: $showValues)
                Button(copied ? String("Copiato") : String("Copia il report")) {
                    UIPasteboard.general.string = report
                    copied = true
                }
                .disabled(payloads.isEmpty)
            } footer: {
                Text(verbatim: "Cerca i campi con ★: codice del corso di studi (k_corso_la), del piano (k_indir), della classe (c_classe). Ripeti con ogni matricola.")
            }
            .lookRow()

            if loading {
                Section { ProgressView().frame(maxWidth: .infinity) }
                .lookRow()
            }

            if !checks.isEmpty {
                Section {
                    ForEach(checks) { check in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: check.name).font(.subheadline.weight(.medium))
                            Text(verbatim: "c_insegn_piano \(check.code) · c_classe_m \(check.classID)")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(verbatim: verdict(check)).font(.caption)
                                .foregroundStyle(color(check))
                        }
                    }
                } header: {
                    Text(verbatim: "c_classe_m è la classe del Manifesto?")
                } footer: {
                    Text(verbatim: "Per ogni insegnamento con appelli apre SchedaPublic.do?c_classe=c_classe_m e confronta i docenti con docente_esame.")
                }
                .lookRow()
            }

            ForEach(payloads) { payload in
                Section {
                    if let error = payload.error {
                        Text(verbatim: error).foregroundStyle(.orange)
                    }
                    ForEach(payload.fields) { field in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: field.path).font(.caption.monospaced())
                                .foregroundStyle(PayloadInspector.isInteresting(field.path) ? Theme.brand : .primary)
                            Spacer()
                            Text(verbatim: [field.type, field.sample.map { showValues ? $0 : PayloadInspector.mask($0) }]
                                .compactMap { $0 }.joined(separator: " = "))
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .textSelection(.enabled)
                    }
                } header: {
                    Text(verbatim: payload.title)
                }
                .lookRow()
            }
        }
        .lookList()
        .navigationTitle(String("Diagnostica carriera"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if payloads.isEmpty { await load() } }
        .onChange(of: showValues) { copied = false }
    }

    private var report: String {
        let header = "Diagnostica carriera · matricola \(showValues ? (session.student?.matricola ?? "—") : PayloadInspector.mask(session.student?.matricola ?? "—"))"
        let sections = payloads.map { payload in
            payload.error.map { "\(payload.title)\n  errore: \($0)" }
                ?? PayloadInspector.report(title: payload.title, fields: payload.fields, showValues: showValues)
        }
        let classes = checks.isEmpty ? [] : ["c_classe_m → scheda"] + checks.map { "  \($0.code) \($0.classID): \(verdict($0))" }
        return ([header] + sections + classes).joined(separator: "\n\n")
    }

    private func verdict(_ check: ClassCheck) -> String {
        guard let scheda = check.schedaLecturers else { return "nessuna scheda con questa classe" }
        guard let exam = check.examLecturer, !exam.isEmpty else { return "scheda: \(scheda.joined(separator: ", ")); nessun docente d'esame" }
        let names = showValues ? " (\(scheda.joined(separator: ", ")))" : ""
        return PayloadInspector.sameLecturer(exam: exam, scheda: scheda)
            ? "combacia: la scheda della classe ha il docente d'esame\(names)"
            : "non combacia\(names)"
    }

    private func color(_ check: ClassCheck) -> Color {
        guard let scheda = check.schedaLecturers, let exam = check.examLecturer else { return .secondary }
        return PayloadInspector.sameLecturer(exam: exam, scheda: scheda) ? .green : .orange
    }

    private func load() async {
        guard let matricola = session.student?.matricola else { return }
        loading = true
        defer { loading = false }
        let requests: [(String, APIRequest)] = [
            ("app /v1/careers/list", APIRequest(host: .app, path: "/v1/careers/list")),
            ("libretto /testatapiano", APIRequest(host: .libretto, path: "/testatapiano/\(matricola)")),
            ("libretto /elencoinsegnamenti", APIRequest(host: .libretto, path: "/elencoinsegnamenti/\(matricola)")),
            ("iae /v1/insegn", APIRequest(host: .iae, path: "/v1/insegn",
                                          query: [.init(name: "lang", value: PoliMiLanguage.current.rawValue)])),
        ]
        var loaded: [Payload] = []
        var insegn: Data?
        for (title, request) in requests {
            var payload = Payload(id: title, title: title)
            do {
                let data = try await session.api.send(request)
                if title.hasPrefix("iae") { insegn = data }
                let value = try await BackgroundJSON.decode(JSONValue.self, from: data)
                payload.fields = PayloadInspector.fields(in: value)
            } catch {
                payload.error = error.localizedDescription
            }
            loaded.append(payload)
        }
        payloads = loaded

        guard let insegn, let teachings = try? await BackgroundJSON.decode(TeachingsResponse.self, from: insegn).teachings
        else { return }
        var found: [ClassCheck] = []
        for teaching in teachings.prefix(12) {
            guard let classID = teaching.c_classe_m.map(String.init) else { continue }
            let scheda = await manifesti.syllabus(for: classID)
            found.append(ClassCheck(code: teaching.c_insegn_piano ?? "—", name: teaching.xdescrizione ?? "—",
                                    classID: classID, examLecturer: teaching.docente_esame,
                                    schedaLecturers: scheda.map { $0.teachers.map(\.name) }))
        }
        checks = found
    }
}
#endif

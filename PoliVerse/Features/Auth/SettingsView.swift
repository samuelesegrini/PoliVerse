import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session

    var body: some View {
        @Bindable var session = session

        Form {
            if let student = session.student {
                Section("Account") {
                    LabeledContent("Nome", value: student.fullName)
                    LabeledContent("Matricola", value: student.matricola)
                    LabeledContent("Email", value: student.email)
                }
            }

            Section {
                Toggle("Usa dati di esempio", isOn: $session.useMockData)
            } footer: {
                Text("Con i dati di esempio l'app funziona senza collegarsi ai server del Politecnico. Disattivalo per usare il tuo account reale.")
            }

            Section {
                Button("Esci", role: .destructive) {
                    Task { await session.signOut() }
                }
            }

            Section {
                LabeledContent("Versione", value: Bundle.main.appVersion)
            } footer: {
                Text("PoliVerse non è affiliata al Politecnico di Milano.")
            }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

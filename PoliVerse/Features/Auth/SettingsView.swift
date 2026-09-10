import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @State private var cacheBytes = DiskCache.sizeInBytes()

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

            Section("Dati") {
                LabeledContent("Cache") {
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(cacheBytes), countStyle: .file))
                }
                Button("Svuota cache") {
                    DiskCache.clear()
                    cacheBytes = 0
                }
            }

            Section {
                Button("Esci", role: .destructive) {
                    Task {
                        DiskCache.clear()
                        await session.signOut()
                    }
                }
            } footer: {
                Text("Uscendo vengono rimossi i token dal portachiavi e i dati salvati sul dispositivo.")
            }

            Section {
                LabeledContent("Versione", value: Bundle.main.appVersion)
            } footer: {
                Text("PoliVerse non è affiliata al Politecnico di Milano.")
            }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { cacheBytes = DiskCache.sizeInBytes() }
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

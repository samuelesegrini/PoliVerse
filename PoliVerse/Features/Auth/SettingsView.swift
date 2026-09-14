import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep
    @Environment(CareersService.self) private var careers
    @State private var cacheBytes = DiskCache.sizeInBytes()
    @State private var materialBytes = FileDownloadService.storageInBytes()
    @State private var showingDiagnostics = false

    var body: some View {
        @Bindable var session = session

        Form {
            if let student = session.student {
                Section("Account") {
                    LabeledContent("Nome", value: student.fullName)
                    LabeledContent("Codice persona", value: student.personCode)
                    if careers.hasChoice {
                        NavigationLink {
                            CareerSwitchView()
                        } label: {
                            LabeledContent("Matricola") {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(student.matricola)
                                    if let current = careers.current {
                                        Text(current.label)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        LabeledContent("Matricola", value: student.matricola)
                    }
                    LabeledContent("Email", value: student.email)
                }
                .task { await careers.load() }
            }

            Section {
                Toggle("Usa dati di esempio", isOn: $session.useMockData)
            } footer: {
                Text("Con i dati di esempio l'app funziona senza collegarsi ai server del Politecnico. Disattivalo per usare il tuo account reale.")
            }

            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Promemoria", systemImage: "bell")
                }
            }

            Section("WeBeep") {
                LabeledContent("Accesso") {
                    Text(weBeep.isAuthenticated ? "Collegato" : "Non collegato")
                        .foregroundStyle(weBeep.isAuthenticated ? .green : .secondary)
                }
                if weBeep.isAuthenticated {
                    Button("Scollega WeBeep", role: .destructive) { weBeep.signOut() }
                }
            }

            Section("Dati") {
                LabeledContent("Cache") {
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(cacheBytes), countStyle: .file))
                }
                LabeledContent("Materiali scaricati") {
                    Text(ByteCountFormatter.string(
                        fromByteCount: Int64(materialBytes), countStyle: .file))
                }
                Button("Svuota cache") {
                    DiskCache.clear()
                    OfflineStore.shared.clearAll()
                    cacheBytes = 0
                }
                Button("Elimina materiali scaricati", role: .destructive) {
                    FileDownloadService.clearStorage()
                    materialBytes = 0
                }
            }

            Section {
                DisclosureGroup("Diagnostica", isExpanded: $showingDiagnostics) {
                    LabeledContent("Profilo", value: String(session.profileID))
                    LabeledContent("Servizi") {
                        Text(session.directory.didLoad ? "Caricati" : "Predefiniti")
                    }
                    ForEach(ServiceDirectory.Service.allCases, id: \.rawValue) { service in
                        LabeledContent(service.rawValue) {
                            Text(session.directory.baseURL(for: service).absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent("Scope OAuth") {
                        Text("\(session.directory.oauth.scope.split(separator: " ").count) ambiti")
                    }
                    LabeledContent("Servizi dati") {
                        Text(session.serviceAuthorizationFailed ? "Non autorizzati" : "OK")
                            .foregroundStyle(session.serviceAuthorizationFailed ? .orange : .green)
                    }
                    #if DEBUG
                    NavigationLink {
                        MetricReportsView()
                    } label: {
                        Text(verbatim: "MetricKit")
                    }
                    NavigationLink {
                        CareerDiagnosticsView()
                    } label: {
                        Text(verbatim: "Diagnostica carriera")
                    }
                    #endif
                }
            } footer: {
                Text("Utile per segnalare un problema: mostra dove l'app sta cercando i servizi del Politecnico.")
            }

            Section {
                Button("Esci", role: .destructive) {
                    Task {
                        DiskCache.clear()
                    OfflineStore.shared.clearAll()
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
        .onAppear {
            cacheBytes = DiskCache.sizeInBytes() + OfflineStore.shared.sizeInBytes
            materialBytes = FileDownloadService.storageInBytes()
        }
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

// MARK: - Previews

#Preview("Impostazioni") {
    SettingsView().previewInNavigation()
}

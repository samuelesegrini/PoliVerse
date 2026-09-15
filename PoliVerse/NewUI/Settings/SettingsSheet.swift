import SwiftUI

/// Settings, opened as a sheet from Oggi: the profile first, then data,
/// appearance, the parts of the university the app reads, and help.
///
/// Areas not rebuilt yet open the current settings screen, so nothing is
/// lost while the new structure is tried out.
struct SettingsSheet: View {
    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @AppStorage(AppLayout.storageKey) private var layout: AppLayout = .tabs
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HStack(spacing: 14) {
                            ProfileAvatar(student: session.student, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.student?.fullName ?? String(localized: "Ospite"))
                                    .font(.headline)
                                Text("Vedi e modifica il profilo")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    NavigationLink {
                        DataStorageView()
                    } label: {
                        Label("Dati e archiviazione", systemImage: "externaldrive")
                    }
                }

                Section {
                    Picker(selection: $layout) {
                        ForEach(AppLayout.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    } label: {
                        Label("Disposizione", systemImage: "square.grid.2x2")
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text(layout.detail)
                }

                Section {
                    NavigationLink {
                        ContentUnavailableView("Aspetto", systemImage: "paintbrush",
                                               description: Text("Colore, motivo e widget della schermata Oggi."))
                    } label: {
                        Label("Aspetto", systemImage: "paintbrush")
                    }
                }

                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Promemoria", systemImage: "bell")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        LabeledContent {
                            Text(weBeep.isAuthenticated ? "Collegato" : "Non collegato")
                        } label: {
                            Label("WeBeep", systemImage: "books.vertical")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Sviluppo e diagnostica", systemImage: "hammer")
                    }
                }

                Section {
                    LabeledContent("Versione", value: Bundle.main.appVersion)
                    Button("Esci", role: .destructive) { confirmingSignOut = true }
                } footer: {
                    Text("PoliVerse non è affiliata al Politecnico di Milano.")
                }
            }
            .navigationTitle("Impostazioni")
            .searchable(text: $query, prompt: "Cerca nelle impostazioni")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi", systemImage: "xmark") { dismiss() }
                }
            }
            .confirmationDialog("Uscire dall’account?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Esci", role: .destructive) {
                    Task { await session.signOut() }
                }
            } message: {
                Text("Vengono rimossi i token dal portachiavi e i dati salvati sul dispositivo.")
            }
        }
    }
}

/// What the app keeps on the device, and the buttons to free it.
struct DataStorageView: View {
    @State private var cacheBytes = DiskCache.sizeInBytes()
    @State private var materialBytes = FileDownloadService.storageInBytes()

    var body: some View {
        List {
            Section {
                LabeledContent("Cache", value: ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))
                Button("Svuota cache") {
                    DiskCache.clear()
                    OfflineStore.shared.clearAll()
                    cacheBytes = 0
                }
            } footer: {
                Text("Orari, corsi e carriera salvati per aprire l’app senza rete.")
            }
            Section {
                LabeledContent("Materiali scaricati", value: ByteCountFormatter.string(fromByteCount: Int64(materialBytes), countStyle: .file))
                Button("Elimina materiali scaricati", role: .destructive) {
                    FileDownloadService.clearStorage()
                    materialBytes = 0
                }
            }
        }
        .navigationTitle("Dati e archiviazione")
    }
}

#Preview("Impostazioni") {
    SettingsSheet().previewEnvironment()
}

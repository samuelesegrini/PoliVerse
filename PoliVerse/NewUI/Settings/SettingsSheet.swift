import SwiftUI

/// Settings, opened as a sheet from Oggi: the profile first, then data,
/// appearance, the parts of the university the app reads, and help.
///
/// Areas not rebuilt yet open the current settings screen, so nothing is
/// lost while the new structure is tried out.
struct SettingsSheet: View {
    @Environment(Session.self) private var session
    @Environment(DataStatus.self) private var status
    @Environment(WeBeepModel.self) private var weBeep
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shell) private var shell

    @AppStorage(NewInterface.storageKey) private var usesNewInterface = true
    @AppStorage(AppLayout.storageKey) private var layout: AppLayout = .tabs
    @AppStorage(SearchTabKeyboard.storageKey) private var searchOpensKeyboard = true
    @State private var confirmingSignOut = false

    #if DEBUG
    /// `-NewUI` shows this interface whatever the setting says, so switching
    /// back would do nothing.
    private let canSwitchBack = !CommandLine.arguments.contains("-NewUI")
    #else
    private let canSwitchBack = true
    #endif

    var body: some View {
        NavigationStack(path: Binding(get: { shell.settingsPath }, set: { shell.settingsPath = $0 })) {
            List {
                Section {
                    NavigationLink(value: ShellState.SettingsPage.profile) {
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
                        // A subtitle under the row rather than a value beside
                        // it: "Dati di esempio" is the kind of thing a student
                        // must be able to read at a glance, and a trailing
                        // value is where the eye goes last and where a long
                        // sentence gets truncated. Always present, so the row
                        // reads the same way whether the news is good or bad —
                        // as the iCloud row does in Impostazioni.
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dati e archiviazione")
                                Text(status.summary)
                                    .font(.caption)
                                    .foregroundStyle(status.badge == nil ? Color.secondary : .orange)
                            }
                        } icon: {
                            Image(systemName: "externaldrive")
                        }
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
                    .accessibilityIdentifier("settings-layout")
                } footer: {
                    Text(layout.detail)
                }

                if layout == .tabs {
                    Section {
                        Toggle(isOn: $searchOpensKeyboard) {
                            Label("Apri la tastiera in Cerca", systemImage: "keyboard")
                        }
                    } footer: {
                        Text(searchOpensKeyboard
                             ? "Toccando Cerca il campo si attiva subito."
                             : "Toccando Cerca vedi prima le ricerche recenti e i luoghi; la tastiera si apre quando tocchi il campo.")
                    }
                }

                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Promemoria", systemImage: "bell")
                    }
                    NavigationLink {
                        ConnectionsView()
                    } label: {
                        LabeledContent {
                            Text(weBeep.isAuthenticated ? "Collegato" : "Non collegato")
                        } label: {
                            Label("WeBeep e diagnostica", systemImage: "books.vertical")
                        }
                    }
                }

                if canSwitchBack {
                    Section {
                        Button {
                            dismiss()
                            usesNewInterface = false
                        } label: {
                            Label("Torna all’interfaccia attuale", systemImage: "arrow.uturn.backward")
                        }
                    } footer: {
                        Text("La nuova interfaccia è in prova. Puoi riattivarla dalle impostazioni.")
                    }
                }

                Section {
                    LabeledContent("Versione", value: Bundle.main.appVersion)
                    Button("Esci", role: .destructive) { confirmingSignOut = true }
                } footer: {
                    Text("PoliVerse non è affiliata al Politecnico di Milano.")
                }
            }
            .accessibilityIdentifier("settings-list")
            .navigationTitle("Impostazioni")
            .navigationDestination(for: ShellState.SettingsPage.self) { page in
                switch page {
                case .profile: ProfileView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("settings-close")
                }
            }
            .confirmationDialog("Uscire dall’account?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Esci", role: .destructive) {
                    Task { await session.login.signOut() }
                }
            } message: {
                Text("Vengono rimossi i token dal portachiavi e i dati salvati sul dispositivo.")
            }
        }
    }
}

#Preview("Impostazioni") {
    SettingsSheet().previewEnvironment()
}

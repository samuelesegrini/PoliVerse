import SwiftUI

/// Settings, opened as a sheet from Oggi: the profile first, then data,
/// appearance, the parts of the university the app reads, and help.
struct SettingsSheet: View {
    /// The shared ``WhatsNewState``, from the environment.
    @Environment(WhatsNewState.self) private var whatsNew
    /// The shared ``OnboardingState``, from the environment.
    @Environment(OnboardingState.self) private var onboarding
    /// Opened from the row below, rather than by the shell: a sheet raised
    /// over this one from outside it never comes up.
    @State private var readingNotes: [ReleaseNote] = []
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``DataStatus``, from the environment.
    @Environment(DataStatus.self) private var status
    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss
    /// The environment's `shell`.
    @Environment(\.shell) private var shell

    /// How the app is laid out: tabs, or one page with a panel.
    @AppStorage(AppLayout.storageKey) private var layout: AppLayout = .tabs
    /// Whether opening Cerca brings the keyboard up.
    @AppStorage(SearchTabKeyboard.storageKey) private var searchOpensKeyboard = true
    /// The shared ``StudyProgrammeModel``, from the environment.
    @Environment(StudyProgrammeModel.self) private var programmes
    /// The shared ``RoomsModel``, from the environment.
    @Environment(RoomsModel.self) private var rooms
    /// The shared ``FreeRoomsModel``, from the environment.
    @Environment(FreeRoomsModel.self) private var freeRooms
    /// The campus Aule libere opens on.
    @AppStorage(FavouriteCampus.storageKey) private var favouriteCampus = ""
    /// Whether the plan picker is up.
    @State private var choosingPlan = false
    /// Whether the sign-out confirmation is presented.
    @State private var confirmingSignOut = false

    /// The degree course and approved plan, and the favourite campus: what the
    /// journey asked, changed later.
    private var studiesSection: some View {
        Section {
            if !session.useMockData {
                Button { choosingPlan = true } label: {
                    LabeledContent {
                        Text(programmes.programme?.planLabel ?? String(localized: "Da scegliere"))
                            .lineLimit(1)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Corso di studi e piano")
                                if let degree = programmes.programme?.degreeLabel {
                                    Text(degree)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        } icon: {
                            Image(systemName: "graduationcap")
                        }
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("settings-programme")
            }
            Picker(selection: Binding(get: { favouriteCampus }, set: { campus in
                favouriteCampus = campus
                freeRooms.campus = campus
            })) {
                if favouriteCampus.isEmpty || !rooms.campuses.contains(favouriteCampus) {
                    Text("Nessuna").tag(favouriteCampus)
                }
                ForEach(rooms.campuses, id: \.self) { Text($0).tag($0) }
            } label: {
                Label("Sede preferita", systemImage: "building.2")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings-campus")
        } header: {
            Text("I tuoi studi")
        } footer: {
            if session.useMockData {
                Text("La sede è dove si aprono le aule libere.")
            } else {
                Text("Il piano approvato (PSPA) decide le schede dei corsi, il syllabus e l’orario personalizzato; la sede è dove si aprono le aule libere.")
            }
        }
        .lookRow()
        .task { await rooms.load() }
        .sheet(isPresented: $choosingPlan) { StudyProgrammeSheet() }
    }

    /// The view's content.
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
                .lookRow()

                studiesSection

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
                .lookRow()

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
                    .lookRow()
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
                .lookRow()

                Section {
                    LabeledContent("Versione", value: Bundle.main.appVersion)
                    // The update's notes are shown once, over an app someone
                    // opened to do something else: this is where they are read
                    // properly, afterwards.
                    if whatsNew.hasCurrentNote {
                        Button { readingNotes = whatsNew.currentNotes } label: {
                            Label("Novità di questa versione", systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("settings-whats-new")
                    }
                    // The first run, again: the tour and the settings it asks
                    // for once. The sheet closes first, because the flow takes
                    // the place of the app underneath it.
                    Button {
                        dismiss()
                        onboarding.replay()
                    } label: {
                        Label("Rivedi il benvenuto", systemImage: "hand.wave")
                    }
                    .accessibilityIdentifier("settings-replay-onboarding")
                    Button("Esci", role: .destructive) { confirmingSignOut = true }
                } footer: {
                    Text("PoliVerse non è affiliata al Politecnico di Milano.")
                }
                .lookRow()
            }
            .accessibilityIdentifier("settings-list")
            .lookList()
            .navigationTitle("Impostazioni")
            .sheet(isPresented: Binding(get: { !readingNotes.isEmpty },
                                        set: { if !$0 { readingNotes = [] } })) {
                WhatsNewView(notes: readingNotes, saysWhereToFindItAgain: false) { readingNotes = [] }
            }
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

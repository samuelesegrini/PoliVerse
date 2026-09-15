import SwiftUI

/// The Oggi tab of the new structure: the day's lessons, exams and deadlines.
///
/// Only the navigation bar is built so far. On the left, the profile menu and
/// settings as two separate glass buttons; in the middle, the day being
/// shown, which opens a date picker; on the right, add and more actions in
/// one glass group.
struct TodayTab: View {
    @Environment(Session.self) private var session
    @Environment(\.locale) private var locale

    @State private var day = Date.now
    @State private var showingDatePicker = false
    @State private var showingSettings = false
    @State private var showingProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ContentUnavailableView("Oggi", systemImage: "calendar.day.timeline.left",
                                       description: Text("Lezioni, esami e scadenze del giorno."))
                    .padding(.top, 120)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showingDatePicker) { datePicker }
            .sheet(isPresented: $showingSettings) { SettingsSheet() }
            .sheet(isPresented: $showingProfile) {
                NavigationStack {
                    ProfileView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Chiudi") { showingProfile = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Profile and settings sit together on the left as two separate glass
        // circles; the shared capsule would join them into one pill.
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 8) {
                profileMenu
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Impostazioni")
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .principal) {
            Button { showingDatePicker = true } label: {
                HStack(spacing: 6) {
                    Text(day.formatted(.dateTime.day().month(.abbreviated).locale(locale)).capitalized)
                        .font(.headline)
                    Image(systemName: "chevron.down.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Giorno mostrato: \(day.formatted(.dateTime.day().month(.wide).locale(locale)))"))
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu("Aggiungi", systemImage: "plus") {
                Button("Promemoria d’esame", systemImage: "pencil.and.list.clipboard") {}
                Button("Scadenza", systemImage: "checklist") {}
            }
            Menu("Altro", systemImage: "ellipsis") {
                Button("Vai a oggi", systemImage: "arrow.uturn.backward") { day = .now }
                    .disabled(Calendar.current.isDateInToday(day))
                Button("Personalizza", systemImage: "paintbrush") {}
            }
        }
    }

    /// The student's profile, the three places they manage, and settings —
    /// the native menu renders the name with the matricola as its subtitle
    /// and the three shortcuts as one horizontal row.
    private var profileMenu: some View {
        Menu {
            Section {
                Button { showingProfile = true } label: {
                    Text(session.student?.fullName ?? String(localized: "Ospite"))
                    Text(session.student.map { String(localized: "Matricola \($0.matricola)") } ?? "")
                }
            }
            ControlGroup {
                Button("Orario", systemImage: "calendar") {}
                Button("Corsi", systemImage: "book.closed") {}
                Button("Docenti", systemImage: "person") {}
            }
            .controlGroupStyle(.compactMenu)
            Section {
                Button("Impostazioni", systemImage: "gearshape") { showingSettings = true }
            }
        } label: {
            ProfileAvatar(student: session.student, size: 36)
                .padding(4)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Profilo")
    }

    private var datePicker: some View {
        NavigationStack {
            DatePicker("Giorno", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .navigationTitle("Scegli un giorno")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Oggi") { day = .now }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fine", systemImage: "checkmark") { showingDatePicker = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Oggi") {
    TodayTab().previewEnvironment()
}

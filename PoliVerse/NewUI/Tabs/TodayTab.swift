import SwiftUI

/// The Oggi tab of the new structure: the day's lessons, exams and deadlines.
///
/// Only the navigation bar is built so far. On the left, the profile menu and
/// settings as two separate glass buttons; in the middle, the day being
/// shown, which opens a day stepper in a popover; on the right, add and more actions in
/// one glass group.
struct TodayTab: View {
    @Environment(Session.self) private var session
    @Environment(\.locale) private var locale

    @State private var day = Date.now
    @State private var showingDays = false
    /// Drives the chevron separately from the popover: bound to `showingDays`
    /// alone, the toolbar only redrew it once the popover had gone.
    @State private var chevronUp = false
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
        // Profile and settings are two glass circles, split by a fixed spacer
        // so the system does not join them; add and more share one capsule.
        ToolbarItem(placement: .topBarLeading) { profileMenu }
        ToolbarSpacer(.fixed, placement: .topBarLeading)
        ToolbarItem(placement: .topBarLeading) {
            Button("Impostazioni", systemImage: "gearshape") { showingSettings = true }
        }

        ToolbarItem(placement: .principal) {
            Button {
                withAnimation(.snappy(duration: 0.3)) { chevronUp.toggle() }
                showingDays.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(day.formatted(.dateTime.day().month(.abbreviated).locale(locale)).capitalized)
                        .font(.headline)
                    Image(systemName: "chevron.down.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(chevronUp ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            // A real popover, kept as one on iPhone: the system morphs it out
            // of the date and back, and closes it on a tap outside.
            .popover(isPresented: $showingDays, arrowEdge: .top) {
                DayStrip(day: $day)
                    .frame(width: 360)
                    .presentationCompactAdaptation(.popover)
            }
            // A tap outside closes the popover without the button: turn the
            // chevron back as soon as that starts.
            .onChange(of: showingDays) { _, showing in
                if chevronUp != showing { withAnimation(.snappy(duration: 0.3)) { chevronUp = showing } }
            }
            .accessibilityLabel(Text("Giorno mostrato: \(day.formatted(.dateTime.day().month(.wide).locale(locale)))"))
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu("Aggiungi", systemImage: "plus") {
                Button("Promemoria d’esame", systemImage: "pencil.and.list.clipboard") {}
                Button("Scadenza", systemImage: "checklist") {}
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
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
            // Laid out at a symbol's width so the bar sizes its glass as the
            // same circle as the other buttons; the photo draws a little
            // larger inside it.
            ProfileAvatar(student: session.student, size: 34)
                .frame(width: 12, height: 12)
        }
        .accessibilityLabel("Profilo")
    }

}

#Preview("Oggi") {
    TodayTab().previewEnvironment()
}

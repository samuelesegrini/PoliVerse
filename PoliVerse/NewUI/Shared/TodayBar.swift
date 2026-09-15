import SwiftUI

/// Oggi's navigation bar, shared by the tab layout and the single page:
/// profile and settings as two glass circles on the left, the day shown in
/// the middle with its stepper popover, add and more on the right.
///
/// The sheets its buttons open are presented by ``NewRootView``, through
/// ``ShellState``, so they survive a change of layout.
struct TodayBar: ViewModifier {

    @Environment(Session.self) private var session
    @Environment(\.locale) private var locale
    @Environment(\.shell) private var shell

    /// Drives the chevron separately from the popover: bound to `showingDays`
    /// alone, the toolbar only redrew it once the popover had gone.
    @State private var chevronUp = false

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Profile and settings are two glass circles, split by a fixed spacer
        // so the system does not join them; add and more share one capsule.
        ToolbarItem(placement: .topBarLeading) { profileMenu }
        ToolbarSpacer(.fixed, placement: .topBarLeading)
        ToolbarItem(placement: .topBarLeading) {
            Button("Impostazioni", systemImage: "gearshape") { shell.present { shell.showingSettings = true } }
        }

        ToolbarItem(placement: .principal) {
            Button {
                withAnimation(.snappy(duration: 0.3)) { chevronUp.toggle() }
                if shell.showingDays { shell.showingDays = false } else { shell.present { shell.showingDays = true } }
            } label: {
                HStack(spacing: 6) {
                    Text(shell.day.formatted(.dateTime.day().month(.abbreviated).locale(locale)).capitalized)
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
            .popover(isPresented: Binding(get: { shell.showingDays }, set: { shell.showingDays = $0 }), arrowEdge: .top) {
                DayStrip(day: Binding(get: { shell.day }, set: { shell.day = $0 }))
                    .frame(width: 360)
                    .presentationCompactAdaptation(.popover)
            }
            // A tap outside closes the popover without the button: turn the
            // chevron back as soon as that starts.
            .onChange(of: shell.showingDays) { _, showing in
                if chevronUp != showing { withAnimation(.snappy(duration: 0.3)) { chevronUp = showing } }
            }
            .accessibilityLabel(Text("Giorno mostrato: \(shell.day.formatted(.dateTime.day().month(.wide).locale(locale)))"))
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu("Aggiungi", systemImage: "plus") {
                Button("Promemoria d’esame", systemImage: "pencil.and.list.clipboard") {}
                Button("Scadenza", systemImage: "checklist") {}
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Altro", systemImage: "ellipsis") {
                Button("Vai a oggi", systemImage: "arrow.uturn.backward") { shell.day = .now }
                    .disabled(Calendar.current.isDateInToday(shell.day))
                Button("Personalizza", systemImage: "paintbrush") { shell.present { shell.isCustomizing = true } }
                    .accessibilityIdentifier("today-customize")
            }
        }
    }

    /// The student's profile, the three places they manage, and settings —
    /// the native menu renders the name with the matricola as its subtitle
    /// and the three shortcuts as one horizontal row.
    private var profileMenu: some View {
        Menu {
            Section {
                Button { shell.present { shell.showingProfile = true } } label: {
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
                Button("Impostazioni", systemImage: "gearshape") { shell.present { shell.showingSettings = true } }
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

extension View {
    func todayBar() -> some View {
        modifier(TodayBar())
    }
}

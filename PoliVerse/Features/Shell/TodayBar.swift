import SwiftUI

/// Oggi's navigation bar, shared by the tab layout and the single page:
/// profile and settings as two glass circles on the left, the day shown in
/// the middle with its stepper popover, Personalizza on the right.
///
/// Settings and Personalizza stay whatever the look hides: without them
/// there would be no way back to either. The sheets its buttons open are
/// presented by ``RootView``, through ``ShellState``, so they survive a
/// change of layout.
struct TodayBar: ViewModifier {

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// Which buttons the look in use keeps in the bar.
    @Environment(\.look) private var style

    /// Drives the chevron separately from the popover: bound to `showingDays`
    /// alone, the toolbar only redrew it once the popover had gone.
    @State private var chevronUp = false

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
    }

    // MARK: - Toolbar

    /// Oggi's bar: the profile and settings circles leading, the date in the middle, and the way into Personalizza trailing.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Profile and settings are two glass circles, split by a fixed spacer
        // so the system does not join them.
        if style.bar.showsProfile {
            ToolbarItem(placement: .topBarLeading) { ProfileBarButton() }
            ToolbarSpacer(.fixed, placement: .topBarLeading)
        }
        ToolbarItem(placement: .topBarLeading) { SettingsBarButton() }

        if style.bar.showsDate {
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
        }

        // The calendar opens from the day, where the question "when" lives.
        ToolbarItem(placement: .topBarTrailing) {
            Button("Calendario", systemImage: "calendar") { shell.todayPath.append(NewDestination.calendar) }
                .accessibilityIdentifier("today-calendar")
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button("Personalizza", systemImage: "paintbrush") { shell.present { shell.isCustomizing = true } }
                .accessibilityIdentifier("today-customize")
        }
    }
}

/// Putting Oggi's bar on a screen.
extension View {
    /// Draws Oggi's navigation bar over this view.
    ///
    /// - Returns: The view, with the bar.
    func todayBar() -> some View {
        modifier(TodayBar())
    }
}

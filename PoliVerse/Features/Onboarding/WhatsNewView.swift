import SwiftUI

/// What changed in this update, once per update.
///
/// Shown over the app after an upgrade, never on a fresh install — a student
/// who has just been through the tour is not owed a list of changes to a
/// version they never ran. Re-openable afterwards from Impostazioni, because
/// the one time it appears is the one time nobody is ready to read it.
///
/// The content is ``ReleaseNotes/all``, which is the file to edit before a
/// release. This view only lays it out.
struct WhatsNewView: View {
    /// The releases to show, newest first.
    let notes: [ReleaseNote]
    /// False when this *is* the page in Impostazioni, where saying where to
    /// find it again is saying where you already are.
    var saysWhereToFindItAgain = true
    /// Dismisses the screen.
    let done: () -> Void

    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// The look in use, which supplies the colours.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// The `iconSide`, scaled with the reader's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var iconSide: CGFloat = 76

    /// The look's colours for the current appearance.
    private var palette: Flavor.Palette { style.palette(scheme) }

    /// The view's content.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 26) {
                    header
                    ForEach(notes) { note in
                        release(note)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                OnboardingPrimaryButton(title: "Continua", action: done)
                if saysWhereToFindItAgain {
                    Text("Le trovi di nuovo in Impostazioni · Novità.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .presentationDragIndicator(.visible)
    }

    /// The tile, the title, and the newest release's headline.
    private var header: some View {
        VStack(spacing: 14) {
            GlassTile(symbol: "sparkles", colour: style.controlAccent(dark: scheme == .dark), side: iconSide, surface: .glass)
            Text("Novità di PoliVerse")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            if let first = notes.first {
                Text(first.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// One release as a card of its items.
    ///
    /// - Parameter note: The release to lay out.
    /// - Returns: The card.
    private func release(_ note: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Named only when more than one update is being caught up on:
            // alone, "Versione 2.1" over its own items says nothing.
            if notes.count > 1 {
                Text("Versione \(note.version)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                ForEach(Array(note.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { CardDivider(inset: 62) }
                    row(item)
                }
            }
            .lookCard()
        }
    }

    /// One change: its symbol, title and description.
    ///
    /// - Parameter item: The change to lay out.
    /// - Returns: The row.
    private func row(_ item: ReleaseNote.Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 34, height: 34)
                .background(palette.accent.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Novità") {
    WhatsNewView(notes: ReleaseNotes.all, done: {}).previewEnvironment()
}

import SwiftUI

// Oggi's look carried to the pages past it — with one thing deliberately left
// behind.
//
// **Oggi keeps the page.** Its paper, its decoration and its colour are drawn
// by ``TodayTab`` alone. Oggi is a poster: one huge date, a few cards, most of
// the page empty, and a pattern of coriandoli or stars reads as design there.
// The rest of the app is dense — a settings list, a libretto, a plan of forty
// teachings — and the same pattern behind small secondary text is noise.
//
// **Everything else travels.** The Flavor's colours, the typeface, the
// material the cards are made of and the light or dark the look asks for go on
// every screen, so the app is recognisably the student's wherever they are
// without any page having to fight its own background.

extension View {
    /// A card in the look's material, as Oggi's sections draw theirs.
    func lookCard(cornerRadius: CGFloat = 26) -> some View {
        modifier(LookCard(cornerRadius: cornerRadius))
    }

    /// The look's colour on the app's controls, and the lighting it asks for.
    ///
    /// Belongs outside anything that presents a sheet. A sheet's content takes
    /// the environment of the view the presentation is attached to, so a tint
    /// applied under one stops at the sheet's edge and the sheet reverts to
    /// the system's blue.
    func lookControls() -> some View {
        modifier(LookControls())
    }
}

private struct LookControls: ViewModifier {
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .tint(style.controlTint(scheme))
            .fontDesign(style.textDesign.design)
            .preferredColorScheme(style.appearance.colorScheme)
    }
}

private struct LookCard: ViewModifier {
    let cornerRadius: CGFloat
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    func body(content: Content) -> some View {
        content.todayMaterial(style.material, flavor: style.flavor, mode: style.appearance.flavorMode,
                              cornerRadius: cornerRadius)
    }
}

/// A block's title, as Oggi's sections have it: plain and semibold, with an
/// optional trailing control such as "Tutti".
struct LookHeading<Trailing: View>: View {
    let title: Text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
                .font(.subheadline)
        }
        .padding(.horizontal, 4)
    }
}

extension LookHeading where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.title = Text(title)
        trailing = EmptyView()
    }

    init(verbatim title: String) {
        self.title = Text(verbatim: title)
        trailing = EmptyView()
    }
}

extension LookHeading {
    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(title)
        self.trailing = trailing()
    }

    init(verbatim title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(verbatim: title)
        self.trailing = trailing()
    }
}

/// A page title in the typeface the look gives Oggi's date, so the pages past
/// Oggi open with the same voice. Smaller than the date: it names a place
/// rather than being the page's news.
struct LookTitle: View {
    let title: Text
    var subtitle: Text?

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme

    init(_ title: LocalizedStringKey, subtitle: Text? = nil) {
        self.title = Text(title)
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: style.dateAlignment.horizontal, spacing: 4) {
            if let subtitle {
                subtitle
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .fontDesign(style.textDesign.design)
                    .contentTransition(.numericText())
            }
            title
                .font(style.dateFont.font(size: 46 * style.dateSize, weight: style.dateWeight))
                .foregroundStyle(style.dateTint(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: style.dateAlignment.frame)
    }
}

/// A capsule to pick one of a few, in the look's colour when chosen.
struct LookChip: View {
    let title: Text
    let isOn: Bool
    var systemImage: String?
    let action: () -> Void

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = style.palette(scheme)
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
                title
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .foregroundStyle(isOn ? palette.onAccent : Color.primary)
            .background {
                if isOn {
                    Capsule().fill(palette.accent)
                }
            }
            .modifier(ChipSurface(isOn: isOn))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// An unchosen chip sits on the look's material; a chosen one is its colour.
private struct ChipSurface: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content
        } else {
            content.lookCard(cornerRadius: 17)
        }
    }
}

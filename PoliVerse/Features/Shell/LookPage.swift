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

/// The look's card and controls, applied to any view.
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

/// The look's tint, typeface and appearance, put on the environment.
private struct LookControls: ViewModifier {
    /// The look in use.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        content
            .tint(style.controlTint(scheme))
            .fontDesign(style.textDesign.design)
            .preferredColorScheme(style.appearance.colorScheme)
    }
}

/// The look's material behind a view, rounded to the given radius.
private struct LookCard: ViewModifier {
    /// How far the card's corners are rounded.
    let cornerRadius: CGFloat
    /// The look in use, which supplies the material.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        content.todayMaterial(style.material, flavor: style.flavor, mode: style.appearance.flavorMode,
                              cornerRadius: cornerRadius)
    }
}

/// A block's title, as Oggi's sections have it: plain and semibold, with an
/// optional trailing control such as "Tutti".
struct LookHeading<Trailing: View>: View {
    /// The heading.
    let title: Text
    /// The `trailing` this view draws.
    @ViewBuilder var trailing: Trailing

    /// The view's content.
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

/// Headings with nothing trailing.
extension LookHeading where Trailing == EmptyView {
    /// A heading from a localised key.
    ///
    /// - Parameter title: The heading.
    init(_ title: LocalizedStringKey) {
        self.title = Text(title)
        trailing = EmptyView()
    }

    /// A heading from a string that is already in the right language.
    ///
    /// - Parameter title: The heading.
    init(verbatim title: String) {
        self.title = Text(verbatim: title)
        trailing = EmptyView()
    }
}

/// Headings with a trailing control.
extension LookHeading {
    /// A heading with a trailing control.
    ///
    /// - Parameters:
    ///   - title: The heading.
    ///   - trailing: The control, such as a way through to the rest.
    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(title)
        self.trailing = trailing()
    }

    /// A heading in the right language already, with a trailing control.
    ///
    /// - Parameters:
    ///   - title: The heading.
    ///   - trailing: The control.
    init(verbatim title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(verbatim: title)
        self.trailing = trailing()
    }
}

/// A page title in the typeface the look gives Oggi's date, so the pages past
/// Oggi open with the same voice. Smaller than the date: it names a place
/// rather than being the page's news.
struct LookTitle: View {
    /// The page's name.
    let title: Text
    /// One line over the title, such as what the page counts.
    var subtitle: Text?

    /// The look in use, whose date typeface the title is set in.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// A page title.
    ///
    /// - Parameters:
    ///   - title: The page's name.
    ///   - subtitle: One line over it, if any.
    init(_ title: LocalizedStringKey, subtitle: Text? = nil) {
        self.title = Text(title)
        self.subtitle = subtitle
    }

    /// The view's content.
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
    /// What the chip is called.
    let title: Text
    /// True when this is the chosen chip.
    let isOn: Bool
    /// An SF Symbol before the title, such as the cross that takes a filter off.
    var systemImage: String?
    /// What the tap does.
    let action: () -> Void

    /// The look in use, which supplies the chosen chip's colour.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
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
    /// True when the chip is chosen, and so already has a colour of its own.
    let isOn: Bool

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        if isOn {
            content
        } else {
            content.lookCard(cornerRadius: 17)
        }
    }
}

import SwiftUI

// Oggi's look carried to the pages past it: the sheet the page is printed
// on, the cards in the look's material, the headings as Oggi's sections have
// them. A page that reads the look through these never falls out of step
// with Personalizza.

extension View {
    /// A page printed on the look in use: its paper or decoration behind the
    /// scrolling content, and the look's text design.
    func lookPage() -> some View {
        modifier(LookPage())
    }

    /// A card in the look's material, as Oggi's sections draw theirs.
    func lookCard(cornerRadius: CGFloat = 26) -> some View {
        modifier(LookCard(cornerRadius: cornerRadius))
    }
}

private struct LookPage: ViewModifier {
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    func body(content: Content) -> some View {
        content
            // A List draws its own grey ground over the sheet otherwise.
            .scrollContentBackground(.hidden)
            .background(TodayBackgroundView(style: style).ignoresSafeArea())
            .fontDesign(style.textDesign.design)
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

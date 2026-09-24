import SwiftUI

// Giocherelloso's pieces, shared by its pages: full-colour cards that lean,
// tickets with a tear-off stub, Futura for anything meant to be read from
// across a corridor. Each page keeps its own data and navigation; only the
// drawing lives here.

/// Giocherelloso's two colours in the light the page is in, with the text
/// that reads on each.
struct PlayfulPalette {
    /// The page's colour: the big cards.
    let main: Color
    /// Black or white, whichever reads on ``main``.
    let onMain: Color
    /// The colour that stands out: buttons, the stub of an urgent ticket, the now line.
    let second: Color
    /// Black or white, whichever reads on ``second``.
    let onSecond: Color
    /// ``second`` darkened or lightened until it reads as text on the page.
    let secondText: Color
    /// A pale wash of ``second``, for a ticket's stub that is not urgent.
    let secondWash: Color

    /// The palette of a look in a light.
    ///
    /// - Parameters:
    ///   - style: The look, already resolved.
    ///   - scheme: The light the page is in.
    init(_ style: TodayStyle, scheme: ColorScheme) {
        let flavor = style.flavor
        let dark = scheme == .dark
        let main = flavor.main
        let second = flavor.colour(.accent)
        self.main = main.color
        onMain = Self.ink(on: main)
        self.second = second.color
        onSecond = Self.ink(on: second)
        secondText = flavor.readable(.accent, dark: dark, mode: style.appearance.flavorMode).color
        secondWash = second.color.opacity(dark ? 0.28 : 0.18)
    }

    /// Black or white, whichever has more contrast on a colour.
    private static func ink(on colour: Flavor.RGB) -> Color {
        Flavor.contrast(.white, colour) >= Flavor.contrast(.black, colour) ? .white : .black
    }
}

extension Font {
    /// Giocherelloso's display face: Futura, scaling with the reader's text size.
    ///
    /// - Parameters:
    ///   - size: The size at the default text size.
    ///   - bold: The bold face rather than the medium one.
    ///   - relativeTo: The text style it scales with.
    /// - Returns: The font.
    static func playful(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? "Futura-Bold" : "Futura-Medium", size: size, relativeTo: style)
    }
}

/// A Giocherelloso section heading: Futura, a size up from the system's.
struct PlayfulHeading: View {
    /// The heading.
    let title: LocalizedStringKey

    /// Creates the heading.
    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    /// The view's content.
    var body: some View {
        Text(title)
            .font(.playful(23, relativeTo: .title2))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A small spaced-out label in capitals over a big line, as the cards head themselves.
struct PlayfulKicker: View {
    /// The words, already in capitals where the language allows.
    let text: String
    /// Its colour.
    let colour: Color

    /// The view's content.
    var body: some View {
        Text(text)
            .font(.playful(12, relativeTo: .caption2))
            .tracking(1.4)
            .foregroundStyle(colour)
    }
}

/// A ticket: a stub on the leading edge torn along a dashed line, and the rest.
struct PlayfulTicket<Stub: View, Content: View>: View {
    /// The stub's fill.
    let stubFill: Color
    /// The stub's width.
    var stubWidth: CGFloat = 76
    /// What the stub shows: a count, a date, a mark.
    @ViewBuilder let stub: Stub
    /// What the ticket is for.
    @ViewBuilder let content: Content

    /// The look in use, which supplies the ticket's paper.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        HStack(spacing: 0) {
            stub
                .frame(width: stubWidth)
                .frame(maxHeight: .infinity)
                .background(stubFill)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .frame(width: 2)
                        .foregroundStyle(.black.opacity(0.18))
                }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(style.flavor.surface(dark: scheme == .dark, mode: style.appearance.flavorMode).color)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    /// Leans a Giocherelloso card by the look's chaos, for its place in a row.
    ///
    /// - Parameters:
    ///   - index: The card's position.
    ///   - style: The look in use.
    /// - Returns: The view, turned.
    func playfulLean(_ index: Int, in style: TodayStyle) -> some View {
        rotationEffect(style.lean(index))
    }
}

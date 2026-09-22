import Foundation
import SwiftUI

// The picture at the top of a settings page, and the colours it is drawn in.
//
// Shared by Dati e archiviazione and WeBeep e diagnostica, so the two pages are
// visibly the same kind of page: one thing in front, in clear glass, with what
// stands behind it tucked under its edges in tinted glass; every mark coloured
// from the Flavor of the look in use.

/// One tile of the picture.
struct HeroTile: Identifiable, Equatable {
    /// The tile's identity, which the animation between pictures tracks.
    let id: String
    /// The tile's SF Symbol.
    let symbol: String
    /// The tile's colour, from the look's ramp.
    let colour: Flavor.RGB
    /// How much this tile weighs against the front one, in whatever unit the
    /// page counts in — bytes for storage. Nil when the page has nothing to
    /// weigh, and the corner alone decides the size.
    var weight: Double?
}

/// A mark on the front tile's corner, like the plus on an "add" icon: the one
/// piece of news the picture carries.
struct HeroBadge: Equatable {
    /// The badge's SF Symbol.
    let symbol: String
    /// The badge's colour.
    let tint: Color
}

/// One thing drawn big, with up to four more behind it.
///
/// The arrangement is the one iCloud's Gestisci spazio uses, and it works for
/// the same reason: an icon is recognised before a label is read, so the page
/// has said what it is about before the eye reaches the first row.
///
/// The four corners are copied from that screen rather than invented, and what
/// makes them work is that **nothing about them is symmetric**: the tiles are
/// four different sizes, the leading pair is bigger than the trailing pair, and
/// the bottom pair hangs lower than the top pair rides high. Four equal squares
/// at four equal offsets read as a diagram of a cross; this reads as a pile of
/// icons, which is the thing being drawn.
struct HeroTileStack: View {
    /// Front first.
    let tiles: [HeroTile]
    /// Drawn alone, in clear glass, when there are no tiles.
    let placeholder: HeroTile
    /// False until there is something to say: a placeholder that flashes for a
    /// frame before the real tiles arrive reads as "empty".
    var showsPlaceholder = true
    /// A mark on the front tile's corner, if any.
    var badge: HeroBadge?
    /// How the look asks its surfaces to be drawn.
    let mode: Flavor.Mode

    /// Scaled, so the picture grows with the reader's text rather than staying
    /// a postage stamp beside a headline they have turned up.
    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 112

    /// One corner, with the height and the size that corner wants — all three
    /// measured off the reference, in units of the front tile's side.
    private struct Slot {
        /// Which side of the front tile: leading or trailing.
        let x: CGFloat
        /// How far above or below the front tile's centre. The two below are
        /// larger than the two above, which is the asymmetry that keeps the
        /// group from reading as a cross.
        let y: CGFloat
        /// The size this position wants before the weights have their say.
        /// Strictly decreasing, so the four are never the same square.
        let scale: CGFloat
    }

    /// Filled in order: the second tile takes the big top-leading corner,
    /// where the eye starts, and the fifth takes the small one.
    private static let slots: [Slot] = [
        Slot(x: -1, y: -0.38, scale: 0.62),
        Slot(x: -1, y: 0.46, scale: 0.52),
        Slot(x: 1, y: -0.32, scale: 0.44),
        Slot(x: 1, y: 0.50, scale: 0.41),
    ]

    /// How much of a tile behind disappears under the front one, as a fraction
    /// of *its own* side — the proportion the reference keeps at every size.
    /// Measured from the front tile's edge rather than from a fixed centre: a
    /// fixed centre leaves a gap behind a small tile and swallows a large one.
    private static let tuck: CGFloat = 0.18

    /// The view's content.
    var body: some View {
        ZStack {
            if let front = tiles.first {
                // With a badge, the bottom-trailing corner is the badge's: a
                // tile there sits under it and the corner reads as a tangle.
                ForEach(Array(tiles.dropFirst().prefix(Self.slots.count - (badge == nil ? 0 : 1)).enumerated()),
                        id: \.element.id) { index, tile in
                    let slot = Self.slots[index]
                    let size = side * scale(of: tile, against: front, in: slot)
                    GlassTile(symbol: tile.symbol, colour: tile.colour, side: size,
                              surface: .tintedGlass, mode: mode)
                        .offset(x: slot.x * (side / 2 + size * (0.5 - Self.tuck)),
                                y: slot.y * side)
                }
                GlassTile(symbol: front.symbol, colour: front.colour, side: side, surface: .glass, mode: mode)
                    .overlay(alignment: .bottomTrailing) { badgeView }
            } else {
                GlassTile(symbol: placeholder.symbol, colour: placeholder.colour, side: side,
                          surface: .glass, mode: mode)
                    .opacity(showsPlaceholder ? 1 : 0)
            }
        }
        // Tall enough for the lowest corner at its largest: half a side down
        // plus half a tile, on both sides of the front tile.
        .frame(height: side * 1.6)
        .animation(.snappy(duration: 0.4), value: tiles)
        .animation(.snappy(duration: 0.3), value: badge)
        // Decorative: every page that draws it names each tile in its rows,
        // and a VoiceOver reader has no use for "a picture of them".
        .accessibilityHidden(true)
    }

    /// The mark on the front tile's corner, in its own colour.
    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            let diameter = side * 0.3
            Circle()
                .fill(badge.tint.gradient)
                .frame(width: diameter, height: diameter)
                .overlay {
                    Image(systemName: badge.symbol)
                        .font(.system(size: diameter * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                // A ring in the page's own colour, so the badge reads as a
                // separate object sitting on the corner — the notch SF Symbols
                // cuts behind its badges.
                .overlay { Circle().strokeBorder(Color(.systemGroupedBackground), lineWidth: diameter * 0.09) }
                .offset(x: diameter * 0.28, y: diameter * 0.28)
                .transition(.scale.combined(with: .opacity))
        }
    }

    /// How big a tile behind is drawn: what its weight asks for, met halfway
    /// with what its corner asks for.
    ///
    /// Weights alone are the honest answer and the wrong picture. Real storage
    /// is lopsided — a term of recordings against a handful of PDFs — so
    /// strictly proportional tiles collapse into one big square and three
    /// identical specks. The fourth root spreads the tail, so a tile at a tenth
    /// of the front draws at 56% instead of 32%; the geometric mean with the
    /// corner's own size then keeps the four visibly different even when the
    /// data is extreme, while a genuinely large second place still grows.
    ///
    /// This is the picture, not the measurement: the exact figures are in the
    /// rows, where nothing is rounded in anyone's favour.
    private func scale(of tile: HeroTile, against front: HeroTile, in slot: Slot) -> CGFloat {
        guard let weight = tile.weight, let frontWeight = front.weight,
              weight > 0, frontWeight > 0 else { return slot.scale }
        let byWeight = min(1, pow(weight / frontWeight, 0.25)) * 0.68
        return (byWeight * slot.scale).squareRoot()
    }
}

/// A squircle, a colour and a symbol, drawn the way an app icon is.
struct GlassTile: View {
    /// What the tile is made of.
    enum Surface {
        /// A filled squircle with a black or white symbol: the small icon in a
        /// row, where it has to read at 30 points on a white card.
        case solid
        /// Liquid Glass tinted with the tile's colour, as Oggi's sections are
        /// in the Vetro tinto material, with the symbol in that colour.
        case tintedGlass
        /// Plain Liquid Glass with an outlined symbol carrying the colour as a
        /// gradient: the front tile, which should read as an object rather
        /// than as a swatch.
        case glass
    }

    /// The tile's SF Symbol.
    let symbol: String
    /// The tile's colour.
    let colour: Flavor.RGB
    /// The tile's side, in points; every other measurement follows from it.
    let side: CGFloat
    /// How the tile is drawn: solid, tinted glass, or clear glass.
    var surface: Surface = .solid
    /// How the look asks its surfaces to be drawn.
    var mode: Flavor.Mode = .standard

    /// The squircle's corner radius, in the proportion iOS gives an app icon.
    private var radius: CGFloat { side * 0.2237 }

    /// The view's content.
    var body: some View {
        switch surface {
        case .solid:
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(colour.color.gradient)
                .frame(width: side, height: side)
                .overlay { glyph(size: 0.42).foregroundStyle(colour.legibleGlyph) }
                // Tiles overlap, so each needs an edge of its own: without the
                // shadow they read as one torn shape.
                .shadow(color: .black.opacity(0.22), radius: side * 0.08, y: side * 0.04)
        case .tintedGlass:
            Color.clear
                .frame(width: side, height: side)
                // The modifier Oggi's sections use, fed a Flavor made of this
                // tile's colour: the same glass at the same tint strength, so
                // the settings pages and the home screen are visibly one app.
                .todayMaterial(.tintedGlass, flavor: Flavor(main: colour), mode: mode, cornerRadius: radius)
                .overlay { glyph(size: 0.46).symbolVariant(.fill).foregroundStyle(colour.color) }
        case .glass:
            Color.clear
                .frame(width: side, height: side)
                .todayMaterial(.glass, flavor: Flavor(main: colour), mode: mode, cornerRadius: radius)
                // Outlined, not filled: on clear glass a filled glyph becomes a
                // solid slab that fights the glass for attention, and the tiles
                // behind already carry the filled weight.
                .overlay { glyph(size: 0.5).foregroundStyle(colour.heroGradient) }
                // The glass alone is nearly the colour of the page; a soft lift
                // separates it from the tinted tiles behind.
                .shadow(color: .black.opacity(0.12), radius: side * 0.1, y: side * 0.05)
        }
    }

    /// The tile's symbol at a share of its side.
    ///
    /// - Parameter size: The symbol's size as a fraction of ``side``.
    /// - Returns: The symbol.
    private func glyph(size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: side * size, weight: .medium))
    }
}

/// Colours a hero tile derives from its own.
extension Flavor.RGB {
    /// Black or white on this colour, whichever reads — the choice
    /// ``Flavor/onAccent(dark:mode:)`` makes, per colour because a ramp runs
    /// from deep to pale and a fixed white would vanish at one end.
    var legibleGlyph: Color {
        Flavor.contrast(.white, self) >= Flavor.contrast(.black, self)
            ? Flavor.RGB.white.color : Flavor.RGB.black.color
    }

    /// Lit from the top corner and deepening towards the bottom, so an outline
    /// symbol reads as a material rather than a flat ink.
    var heroGradient: LinearGradient {
        let (hue, saturation, brightness) = hsb
        let light = Flavor.RGB(hue: hue, saturation: saturation * 0.6, brightness: min(brightness + 0.32, 1))
        let deep = Flavor.RGB(hue: hue, saturation: min(saturation * 1.1, 1), brightness: brightness * 0.68)
        return LinearGradient(colors: [light.color, deep.color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Colours for a page's marks, built from the look the student chose.
///
/// Not system colours per kind — a red PDF, a green spreadsheet — which would
/// ignore the Flavor the student picked and make a settings page read as one
/// borrowed from somewhere else.
///
/// Instead colours come in a ramp from deep to pale around the Flavor's hue,
/// and a page hands out steps by **position**: storage by size, so deeper means
/// bigger, the way iCloud's bar steps from dark to light green. A fixed colour
/// per item would not do it: ten items from one hue leave neighbours a shade
/// apart. Spreading only the items actually on screen gives
/// them the whole ramp between them.
///
/// A colourful Flavor gives a narrow hue ramp; a grey one gives a lightness
/// ramp only, because spreading hues around a grey would invent a colour the
/// student deliberately did not pick — the refusal ``Flavor/derived`` makes.
struct FlavorRamp {
    /// The look's Flavor, which the ramp is centred on.
    let flavor: Flavor
    /// How the look asks its surfaces to be drawn.
    let mode: Flavor.Mode
    /// True in dark mode, which flips the ramp's direction.
    private let dark: Bool
    /// The colour the ramp is checked for contrast against.
    private let ground: Flavor.RGB

    /// How much of the colour wheel the ramp covers, centred on the Flavor's
    /// hue. A sixth: roughly the span of "blues". Much wider and a navy look
    /// would give a green PDF and a purple archive.
    private static let spread = 0.16

    /// The ramp for a look.
    ///
    /// - Parameters:
    ///   - style: The look in use.
    ///   - scheme: Light or dark.
    init(style: TodayStyle, scheme: ColorScheme) {
        flavor = style.flavor
        mode = style.appearance.flavorMode
        dark = scheme == .dark
        ground = flavor.ground(dark: dark, mode: mode)
    }

    /// A ramp around another colour — a course's — still checked against the
    /// look's own page, so its marks read on the sheet they are drawn on.
    init(colour: Flavor.RGB, style: TodayStyle, scheme: ColorScheme) {
        flavor = Flavor(main: colour)
        mode = style.appearance.flavorMode
        dark = scheme == .dark
        ground = style.flavor.ground(dark: dark, mode: mode)
    }

    /// `count` colours, deepest first.
    func colours(_ count: Int) -> [Flavor.RGB] {
        (0..<count).map { index in
            colour(at: count > 1 ? Double(index) / Double(count - 1) : 0)
        }
    }

    /// The colour at a place on the ramp, from 0 (deepest) to 1 (palest).
    func colour(at position: Double) -> Flavor.RGB {
        let (hue, saturation, _) = flavor.main.hsb
        // The threshold ``Flavor/derived`` uses to decide a colour has no hue
        // worth moving along.
        let isGrey = saturation < 0.12
        return visible(Flavor.RGB(
            hue: isGrey ? hue : hue + Self.spread * (position - 0.5),
            // Floored, so a washed-out Flavor still gives marks that read;
            // capped, so a fluorescent one does not glare.
            saturation: isGrey ? saturation : saturation.clamped(to: 0.40...0.95),
            // Its own lightness range rather than the Flavor's: a deep navy
            // look would otherwise give every mark a near-black.
            brightness: 0.48 + 0.42 * position.clamped(to: 0...1)))
    }

    /// The Flavor with the colour taken out: placeholders, the rest of a bar,
    /// anything that is plainly not one of the items.
    var neutral: Flavor.RGB {
        let (hue, saturation, _) = flavor.main.hsb
        return visible(Flavor.RGB(hue: hue, saturation: saturation * 0.12, brightness: dark ? 0.42 : 0.72))
    }

    /// Nudges a colour until it clears the page, the way
    /// ``Flavor/readable(_:dark:mode:)`` does for the roles: a dark look would
    /// otherwise draw near-black marks on a near-black ground.
    private func visible(_ colour: Flavor.RGB) -> Flavor.RGB {
        var candidate = colour
        let (hue, saturation, start) = colour.hsb
        var brightness = start
        var steps = 0
        while Flavor.contrast(candidate, ground) < Flavor.readable, steps < 40 {
            brightness = dark ? min(brightness + 0.04, 1) : max(brightness - 0.04, 0)
            candidate = Flavor.RGB(hue: hue, saturation: saturation, brightness: brightness)
            steps += 1
        }
        return candidate
    }
}

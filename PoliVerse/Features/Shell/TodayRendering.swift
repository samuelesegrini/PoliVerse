import SwiftUI

/// How Oggi draws its decoration, and a switch back to the old way for each piece.
///
/// Scrolling Oggi hitched at 9–16 ms/s on the iPhone 12 Pro, against Apple's 5,
/// with the app's own code under 1% of the main thread: the cost was in what the
/// GPU redraws as the page moves. Each piece below was changed to draw less, and
/// `-TodayLegacy shadow,sheen,stickerEdge,glassContainer` (or `all`) brings the
/// old drawing back, so a device run can weigh each change on its own.
nonisolated enum TodayRendering {
    /// One piece of decoration that was drawn differently before.
    enum Piece: String, CaseIterable, Sendable {
        /// A blurred shadow over a whole card, its text included, rather than
        /// under the card's shape alone.
        case shadow
        /// The lesson cards' lacquer as a shader per card, rather than a gradient.
        case sheen
        /// The sticker edge as a live layer effect, rather than drawn once into a bitmap.
        case stickerEdge
        /// Glass cards each sampled alone, rather than together in one container.
        case glassContainer
    }

    /// The pieces this launch draws the old way.
    static let legacy: Set<Piece> = legacy(in: CommandLine.arguments)

    /// The pieces `-TodayLegacy <list>` names in `arguments`: a comma-separated
    /// list of ``Piece`` names, or `all`. Unknown names are ignored.
    static func legacy(in arguments: [String]) -> Set<Piece> {
        guard let index = arguments.firstIndex(of: "-TodayLegacy"), index + 1 < arguments.count else { return [] }
        let value = arguments[index + 1]
        if value == "all" { return Set(Piece.allCases) }
        return Set(value.split(separator: ",").compactMap { Piece(rawValue: String($0)) })
    }

    /// Whether this launch draws `piece` the old way.
    static func isLegacy(_ piece: Piece) -> Bool { legacy.contains(piece) }

    /// The lacquer of `glossSheen` as a gradient over the fill: a bright band
    /// from the top and a soft shade at the bottom, drawn without a shader pass.
    ///
    /// - Parameter strength: The shader's `strength`, 0 to 1.
    /// - Returns: The gradient to lay over a filled shape.
    static func sheen(strength: Double) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(0.32 * strength), location: 0),
            .init(color: .white.opacity(0.16 * strength), location: 0.2),
            .init(color: .white.opacity(0), location: 0.55),
            .init(color: .black.opacity(0.07 * strength), location: 0.8),
            .init(color: .black.opacity(0.14 * strength), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// A filled card behind the content, with its shadow cast by the card's shape alone.
    ///
    /// A shadow on a view that holds text is drawn offscreen from everything in
    /// it, for every card, on every frame the card moves; from the shape alone it
    /// is one blurred rounded rectangle.
    ///
    /// - Parameters:
    ///   - fill: What the card is filled with.
    ///   - shape: The card's outline.
    ///   - shadow: The shadow's colour.
    ///   - radius: The shadow's blur radius.
    ///   - y: How far the shadow falls below the card.
    /// - Returns: The content on its card.
    func cardBackground<S: Shape, F: ShapeStyle>(_ fill: F, in shape: S, shadow: Color,
                                                 radius: CGFloat, y: CGFloat) -> some View {
        modifier(CardBackground(fill: fill, shape: shape, shadow: shadow, radius: radius, y: y))
    }
}

/// See ``SwiftUI/View/cardBackground(_:in:shadow:radius:y:)``.
private struct CardBackground<S: Shape, F: ShapeStyle>: ViewModifier {
    let fill: F
    let shape: S
    let shadow: Color
    let radius: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        if TodayRendering.isLegacy(.shadow) {
            content
                .background(fill, in: shape)
                .shadow(color: shadow, radius: radius, y: y)
        } else {
            content.background {
                shape.fill(fill).shadow(color: shadow, radius: radius, y: y)
            }
        }
    }
}

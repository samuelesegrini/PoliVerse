import SwiftUI

// MARK: - Shader effects

/// Grain and the sticker edge, as shader effects over any view.
extension View {
    /// Film grain over the view, stable from frame to frame.
    @ViewBuilder
    func paperGrain(_ amount: Double, seed: Double = 1) -> some View {
        // One stack around both cases: callers put this inside reorderable items.
        ZStack {
            if amount > 0 {
                colorEffect(ShaderLibrary.paperGrain(.float(amount * 0.16), .float(seed)))
            } else {
                self
            }
        }
    }

    /// A white cut-out edge around what is drawn, and a soft shadow under it.
    func stickerOutline(_ enabled: Bool, radius: CGFloat = 5) -> some View {
        modifier(StickerOutline(enabled: enabled, radius: radius))
    }
}

/// The white cut-out edge and its shadow, drawn only when asked for.
private struct StickerOutline: ViewModifier {
    /// Whether to draw the edge at all.
    let enabled: Bool
    /// How wide the white edge is, in points.
    let radius: CGFloat

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        ZStack {
            if enabled {
                content
                    // Room for the edge: an effect only draws inside the view.
                    .padding(radius)
                    .layerEffect(ShaderLibrary.stickerOutline(.float(radius), .color(.white)),
                                 maxSampleOffset: CGSize(width: radius, height: radius))
                    .padding(-radius)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            } else {
                content
            }
        }
    }
}

/// A Flavor's three colours drifting slowly, for its tile and preview.
struct FlavorFlowView: View {
    /// The Flavor whose three colours drift.
    let flavor: Flavor
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// iOS 27: the system asks apps to do less — Low Power Mode, a hot device.
    /// A shader redrawn thirty times a second is the first thing to stop.
    @Environment(\.systemPrefersReducedResourceUsage) private var reducedResources

    /// The view's content.
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || reducedResources)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            // Resolved here, on the main actor: the effect closure is Sendable.
            let main = flavor.main.color, accent = flavor.accentColour.color, extra = flavor.extraColour.color
            // An explicit opaque fill: the default foreground in a glass sheet
            // is translucent, and the shader keeps its alpha.
            Rectangle()
                .fill(.white)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.flavorFlow(
                        .float2(proxy.size), .float(time),
                        .color(main), .color(accent), .color(extra)))
                }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Glossy buttons

/// A lacquered button in the Flavor's colours, with a coloured glow: filled
/// for the main action, a light tinted pill for the others.
struct FlavorGlossButtonStyle: ButtonStyle {
    /// Filled for the main action, or a light tinted pill for the others.
    enum Kind { case prominent, tinted }

    /// The Flavor the button is lacquered in.
    let flavor: Flavor
    /// Whether the button is the main action.
    var kind: Kind = .prominent

    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// Draws the button.
    ///
    /// - Parameter configuration: The button's label and whether it is pressed.
    /// - Returns: The styled button.
    func makeBody(configuration: Configuration) -> some View {
        let palette = flavor.palette(scheme)
        let shape = Capsule()
        return configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(kind == .prominent ? palette.onAccent : palette.accent)
            .padding(.horizontal, 20)
            .frame(minHeight: 50)
            .background {
                ZStack {
                    switch kind {
                    case .prominent:
                        shape.fill(LinearGradient(colors: [palette.accentRaw, palette.accent], startPoint: .top, endPoint: .bottom))
                            .visualEffect { content, proxy in
                                content.colorEffect(ShaderLibrary.glossSheen(.float2(proxy.size), .float(1)))
                            }
                    case .tinted:
                        shape.fill(palette.ground)
                            .visualEffect { content, proxy in
                                content.colorEffect(ShaderLibrary.glossSheen(.float2(proxy.size), .float(0.6)))
                            }
                    }
                }
            }
            .overlay {
                shape.strokeBorder(kind == .prominent ? palette.accent.opacity(0.9) : palette.accent.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: palette.mainRaw.opacity(configuration.isPressed ? 0.2 : 0.4), radius: configuration.isPressed ? 6 : 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Accessories

/// What sits beside the date: stickers, a few words, or a stack of photos.
struct TodayAccessoryView: View {
    /// The look, which says which accessory to draw and how.
    let style: TodayStyle
    /// In Personalizza, where an empty accessory shows where things go.
    var editing = false
    /// In Personalizza's arranging mode, where stickers move.
    var arranging = false
    /// Records a change to one sticker.
    var onChange: (UUID, (inout PlacedSticker) -> Void) -> Void = { _, _ in }
    /// Takes one sticker away.
    var onRemove: (UUID) -> Void = { _ in }
    /// Opens the sticker picker.
    var onAdd: () -> Void = {}

    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        ZStack {
            switch style.accessory {
            case .none:
                EmptyView()
            case .stickers:
                StickerPanel(stickers: style.stickers, editing: editing, arranging: arranging, outline: style.stickerOutline,
                             onChange: onChange, onRemove: onRemove, onAdd: onAdd)
            case .text:
                Text(style.accessoryText.isEmpty ? String(localized: "Tutto pronto?") : style.accessoryText)
                    .font(style.dateFont.font(size: 34, weight: max(style.dateWeight, 0.5)))
                    .foregroundStyle(style.accent(scheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .rotationEffect(.degrees(-4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .photos:
                PhotoStack(ids: style.photoIDs)
            }
        }
    }
}

/// Up to three photos, each with a white border, fanned like prints on a desk.
struct PhotoStack: View {
    /// The photos to fan, oldest first; the last is on top.
    let ids: [String]

    /// Each print's offset and tilt, so the stack always falls the same way.
    private static let placements: [(x: CGFloat, y: CGFloat, angle: Double)] = [
        (-0.18, -0.2, -8), (0.2, 0.02, 7), (-0.06, 0.24, -3),
    ]

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.58
            ZStack {
                if ids.isEmpty {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    let place = Self.placements[index % Self.placements.count]
                    StickerContentView(content: .image(id), fill: true)
                        .frame(width: side, height: side)
                        .clipShape(.rect(cornerRadius: 10))
                        .padding(4)
                        .background(.white, in: .rect(cornerRadius: 13))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        .rotationEffect(.degrees(place.angle))
                        .offset(x: place.x * proxy.size.width, y: place.y * proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Foto"))
    }
}

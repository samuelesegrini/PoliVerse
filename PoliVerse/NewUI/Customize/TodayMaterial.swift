import SwiftUI

/// What the page's cards are made of.
nonisolated enum TodayMaterial: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A soft grey fill: the page as it always was.
    case soft
    /// An opaque card in the Flavor's surface colour.
    case solid
    /// Liquid Glass.
    case glass
    /// Liquid Glass that lets more of the background through.
    case clearGlass
    /// Liquid Glass tinted with the Flavor.
    case tintedGlass
    /// The classic blur.
    case frosted
    /// A Flavor card whose edge and sheen go brighter than white on screens
    /// that can show it.
    case glow
    /// No card at all: rows straight on the page. Not `none`, which an
    /// optional material would read as nil.
    case bare

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .soft: "Morbido"
        case .solid: "Pieno"
        case .glass: "Vetro"
        case .clearGlass: "Vetro chiaro"
        case .tintedGlass: "Vetro tinto"
        case .frosted: "Smerigliato"
        case .glow: "Luminoso"
        case .bare: "Nessuno"
        }
    }

    /// Whether rows sit inside a card, with padding around them.
    var hasCard: Bool { self != .bare }
}

extension View {
    /// Draws the view on a card of a material, in a Flavor.
    func todayMaterial(_ material: TodayMaterial, flavor: Flavor, cornerRadius: CGFloat) -> some View {
        modifier(MaterialSurface(material: material, flavor: flavor, cornerRadius: cornerRadius))
    }
}

private struct MaterialSurface: ViewModifier {
    let material: TodayMaterial
    let flavor: Flavor
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let palette = flavor.palette(scheme)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // One stack around every case, so the section above sees a single view.
        ZStack {
            switch material {
            case .soft:
                content.background(.quaternary.opacity(0.5), in: shape)
            case .solid:
                content.background(palette.surface, in: shape)
            case .glass:
                content.glassEffect(.regular, in: shape)
            case .clearGlass:
                content.glassEffect(.clear, in: shape)
            case .tintedGlass:
                content.glassEffect(.regular.tint(palette.accent.opacity(0.3)), in: shape)
            case .frosted:
                content.background(.thinMaterial, in: shape)
            case .glow:
                content
                    .background {
                        ZStack {
                            shape.fill(palette.surface)
                            // A sheen from the top corner, brighter than white.
                            shape.fill(LinearGradient(colors: [palette.accent.hdr(1.2).opacity(0.35), .clear],
                                                      startPoint: .topLeading, endPoint: .center))
                        }
                    }
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(colors: [palette.accent.hdr(1.8), palette.accent.opacity(0.25), palette.accent.hdr(1.2)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.5)
                    }
                    .shadow(color: palette.accent.hdr(1).opacity(0.4), radius: 14)
            case .bare:
                content
            }
        }
    }
}

extension Color {
    /// The colour pushed up by exposure stops, with the headroom it needs, so
    /// HDR screens show it brighter than white and others tone-map it back.
    func hdr(_ stops: Double) -> Color {
        exposureAdjust(stops).headroom(pow(2, stops))
    }
}

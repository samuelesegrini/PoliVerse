#if DEBUG && os(iOS)
import MapKit
import SwiftUI

// The picture at the top of Cerca's room card: the building from above with the room
// pinned, the room's photo, or a drawing of a classroom when there is no photo. Designed
// in the "Cerca · Un'aula" canvas of 13 November 2026 (boards 3, 4 and 6).

/// What the room card's picture shows.
enum RoomHeroMode: Hashable {
    /// The building from above, with the room pinned.
    case map
    /// The room's photo, or the drawing when it has none.
    case room
}

/// Whether a room has a photo, as far as is known yet.
enum RoomPhotoState: Equatable {
    /// The photo index has not answered yet: the map is shown and no switch.
    case unknown
    /// The room has no photo: the switch offers the drawing.
    case absent
    /// The room has a photo with this `idfoto`; the image itself may still be on its way.
    case photo(id: String, image: UIImage?)

    /// The image, once downloaded.
    var image: UIImage? {
        if case .photo(_, let image) = self { image } else { nil }
    }
}

// MARK: - Map

/// The building seen from above, pitched, with realistic elevation: a still from MapKit,
/// made once per building and look and kept for the launch.
///
/// A still rather than a live `Map`: the card is in a scrolling list and morphs from a
/// 64-point thumbnail, which a snapshot scales through without a second map to render.
@MainActor
enum RoomMapSnapshot {
    /// The stills made this launch, by building and look.
    private static var cache: [String: UIImage] = [:]
    /// Stills being made, so two cards of one building wait for the same one.
    private static var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// The size the still is made at, in points: wider and taller than any card, so it can
    /// be cropped to the hero and to the thumbnail from its centre.
    static let size = CGSize(width: 440, height: 260)

    /// A still of a building.
    ///
    /// - Parameters:
    ///   - coordinate: The building's centre, which ends up in the middle of the still.
    ///   - key: The building's code.
    ///   - dark: Whether to draw it in the dark look.
    /// - Returns: The still, or `nil` when MapKit cannot make one.
    static func image(at coordinate: CLLocationCoordinate2D, key: String, dark: Bool) async -> UIImage? {
        let cacheKey = "\(key)-\(dark)"
        if let image = cache[cacheKey] { return image }
        if let task = inFlight[cacheKey] { return await task.value }
        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(lookingAtCenter: coordinate, fromDistance: 520, pitch: 58, heading: 0)
        options.size = size
        options.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = true
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let task = Task<UIImage?, Never> {
            let snapshotter = MKMapSnapshotter(options: options)
            return try? await snapshotter.start().image
        }
        inFlight[cacheKey] = task
        let image = await task.value
        inFlight[cacheKey] = nil
        if let image { cache[cacheKey] = image }
        return image
    }
}

/// The building from above, cropped from the centre to whatever frame it is given, with
/// the room's pin in the middle.
struct RoomMapPicture: View {
    /// The still, or `nil` while it is being made.
    let image: UIImage?
    /// The pin's size: 40 points on the hero, 28 on the thumbnail.
    var pinSize: CGFloat = 40

    var body: some View {
        ZStack {
            Color(.secondarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .overlay { RoomPin(size: pinSize) }
        .clipped()
        .accessibilityElement(children: .ignore)
    }
}

/// The room on the map: an accent disc with a white rim and the door symbol, on a short
/// stem whose tip is the room. Without the stem on the thumbnail.
struct RoomPin: View {
    /// The disc's diameter, rim included.
    var size: CGFloat = 40

    var body: some View {
        let stem = size >= 36
        VStack(spacing: -1) {
            Image(systemName: "door.left.hand.open")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.tint, in: .circle)
                .overlay { Circle().strokeBorder(.white, lineWidth: stem ? 3 : 2.5) }
                .shadow(color: .black.opacity(0.25), radius: 5, y: 4)
            if stem {
                Capsule().fill(.white).frame(width: 3, height: 10)
            }
        }
        // The stem's tip, not the disc's centre, sits on the room.
        .offset(y: stem ? -(size + 9) / 2 : 0)
    }
}

// MARK: - Switch

/// Mappa | Foto (or Mappa | Aula) in glass, centred at the top of the hero.
struct RoomHeroSwitch: View {
    @Binding var mode: RoomHeroMode
    /// "Foto" when the room has a photo, "Aula" when the drawing stands in for it.
    let roomTitle: LocalizedStringKey
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            segment(.map, title: "Mappa")
            segment(.room, title: roomTitle)
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    }

    private func segment(_ value: RoomHeroMode, title: LocalizedStringKey) -> some View {
        let on = mode == value
        return Button {
            withAnimation(.snappy) { mode = value }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background {
                    if on {
                        Capsule()
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

// MARK: - Fade

/// A fade from clear to a colour, eased with smoothstep over many stops so that no band
/// shows where it ends.
struct EasedFade: View {
    /// The colour faded to: the card's.
    let colour: Color

    var body: some View {
        LinearGradient(stops: Self.stops(colour), startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
    }

    /// Sixteen stops on the smoothstep curve.
    static func stops(_ colour: Color) -> [Gradient.Stop] {
        (0...16).map { step in
            let t = Double(step) / 16
            return .init(color: colour.opacity(t * t * (3 - 2 * t)), location: t)
        }
    }
}

/// The colour of the room card and of the grouped lists in Cerca: white in the light look,
/// the raised grey in the dark one.
extension Color {
    static var roomCard: Color { Color(.secondarySystemGroupedBackground) }
}
#endif

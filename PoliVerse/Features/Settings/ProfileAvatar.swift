import SwiftUI

/// How the profile picture is cut. Kept on the device: it is a preference,
/// not account data.
enum AvatarShape: String, CaseIterable, Identifiable {
    /// The three cuts: a circle, a rounded square, and a rosette.
    case circle, roundedSquare, scalloped

    /// The shape's identity, which is its raw value.
    var id: String { rawValue }

    /// What the shape is called in the picker.
    var label: LocalizedStringKey {
        switch self {
        case .circle: "Cerchio"
        case .roundedSquare: "Quadrato"
        case .scalloped: "Coccarda"
        }
    }

    /// The `UserDefaults` key the chosen shape is stored under.
    static let storageKey = "avatarShape"
    /// Whether to show the Politecnico's photo when there is one, or always
    /// the initials.
    static let photoKey = "avatarUsesPhoto"
}

/// The student's photo when the Politecnico has one, their initials otherwise,
/// in the chosen shape.
struct ProfileAvatar: View {
    /// Whose picture to draw, or `nil` before anyone has signed in.
    let student: Student?
    /// The avatar's side, in points.
    var size: CGFloat = 32
    /// Draws this shape instead of the stored one, for pickers that show
    /// every option side by side.
    var shape: AvatarShape? = nil

    /// The shape the student chose, used unless ``shape`` overrides it.
    @AppStorage(AvatarShape.storageKey) private var storedShape: AvatarShape = .circle
    /// Whether to draw the Politecnico's photo, or always the initials.
    @AppStorage(AvatarShape.photoKey) private var usesPhoto = true

    /// The view's content.
    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(clip)
            .accessibilityHidden(true)
    }

    /// The photo when there is one and it is wanted, the initials otherwise.
    @ViewBuilder
    private var content: some View {
        if usesPhoto, let url = student?.photoURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initials
            }
        } else {
            initials
        }
    }

    /// The student's initials on the brand colour.
    private var initials: some View {
        Text(student?.initials ?? "?")
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.brand.gradient)
    }

    /// The shape the avatar is cut to.
    private var clip: AnyShape {
        switch shape ?? storedShape {
        case .circle: AnyShape(Circle())
        case .roundedSquare: AnyShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        case .scalloped: AnyShape(ScallopedCircle())
        }
    }
}

/// A circle with a wavy edge, like a rosette.
nonisolated struct ScallopedCircle: Shape {
    /// How many waves the edge has.
    var lobes = 12

    /// Traces the wavy edge.
    ///
    /// - Parameter rect: The box to fill.
    /// - Returns: The path.
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let depth = outer * 0.06
        var path = Path()
        let steps = 240
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let radius = outer - depth + depth * cos(Double(lobes) * angle)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Avatar") {
    HStack(spacing: 20) {
        ProfileAvatar(student: Student.sample, size: 64)
        ProfileAvatar(student: nil, size: 64)
    }
}

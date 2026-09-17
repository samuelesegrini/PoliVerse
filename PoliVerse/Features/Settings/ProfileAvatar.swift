import SwiftUI

/// How the profile picture is cut. Kept on the device: it is a preference,
/// not account data.
enum AvatarShape: String, CaseIterable, Identifiable {
    case circle, roundedSquare, scalloped

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .circle: "Cerchio"
        case .roundedSquare: "Quadrato"
        case .scalloped: "Coccarda"
        }
    }

    static let storageKey = "avatarShape"
    /// Whether to show the Politecnico's photo when there is one, or always
    /// the initials.
    static let photoKey = "avatarUsesPhoto"
}

/// The student's photo when the Politecnico has one, their initials otherwise,
/// in the chosen shape.
struct ProfileAvatar: View {
    let student: Student?
    var size: CGFloat = 32
    /// Draws this shape instead of the stored one, for pickers that show
    /// every option side by side.
    var shape: AvatarShape? = nil

    @AppStorage(AvatarShape.storageKey) private var storedShape: AvatarShape = .circle
    @AppStorage(AvatarShape.photoKey) private var usesPhoto = true

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(clip)
            .accessibilityHidden(true)
    }

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

    private var initials: some View {
        Text(student?.initials ?? "?")
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.brand.gradient)
    }

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
    var lobes = 12

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

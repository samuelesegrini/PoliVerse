#if DEBUG && os(iOS)
import SwiftUI

/// A classroom drawn from the back, for a room with no photo: rows of desks with their
/// backrests in one-point perspective, a centre aisle, the green blackboard in its wooden
/// frame, the teacher's desk, and windows down the left wall.
///
/// A port of the geometry in the design's `disegno-aula-generatore.py`: the same room, the
/// same camera, drawn into a 322 × 250 frame and scaled to fill whatever it is given,
/// centred, as the mock's `xMidYMid slice` does.
struct ClassroomSketch: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            Self.draw(in: &context, size: size, seat: .style(.tint), palette: palette)
        }
        .background(palette.floor)
        .accessibilityElement()
        .accessibilityLabel(Text("Disegno di un'aula vista dal fondo, con i banchi, la lavagna e la cattedra"))
    }

    /// The room's colours: the mock's in the light look, dimmed in the dark one.
    struct Palette {
        let floor, leftWall, rightWall, backWall, window: Color
        let frame, board, chalk, ledge, deskTop, deskFront, deskSide, deskEdge, seatTop: Color
    }

    private var palette: Palette {
        if scheme == .dark {
            Palette(floor: Color(hex: 0x2A2723), leftWall: Color(hex: 0x312E2A), rightWall: Color(hex: 0x2D2A27),
                    backWall: Color(hex: 0x36332F), window: Color(hex: 0x3A4E5E),
                    frame: Color(hex: 0x6E5638), board: Color(hex: 0x1F3A31), chalk: Color(hex: 0xBFD0C8),
                    ledge: Color(hex: 0x7E6648), deskTop: Color(hex: 0x8C7556), deskFront: Color(hex: 0x6B5235),
                    deskSide: Color(hex: 0x6B5235), deskEdge: Color(hex: 0x7A6244), seatTop: Color(hex: 0xC8C8CC))
        } else {
            Palette(floor: Color(hex: 0xECE7DE), leftWall: Color(hex: 0xF1EDE6), rightWall: Color(hex: 0xEEE9E1),
                    backWall: Color(hex: 0xF6F3EE), window: Color(hex: 0xD6E9F6),
                    frame: Color(hex: 0x9A7A55), board: Color(hex: 0x2E5245), chalk: Color(hex: 0xDCE8E2),
                    ledge: Color(hex: 0xB89A72), deskTop: Color(hex: 0xE2C59C), deskFront: Color(hex: 0xA98159),
                    deskSide: Color(hex: 0xB08A62), deskEdge: Color(hex: 0xC7A57C), seatTop: .white)
        }
    }

    // MARK: - Geometry, as in the generator

    private static let width: CGFloat = 322, height: CGFloat = 250
    private static let cx: CGFloat = 161, f: CGFloat = 150, camH: CGFloat = 4.4, h0: CGFloat = -4
    private static let zw: CGFloat = 15.5, xw: CGFloat = 6.2, yw: CGFloat = 4.2, zn: CGFloat = 2.2

    /// A point of the room on the 322 × 250 drawing.
    private static func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        CGPoint(x: cx + x * f / z, y: h0 + (camH - y) * f / z)
    }

    private static func polygon(_ points: [(CGFloat, CGFloat, CGFloat)]) -> Path {
        var path = Path()
        path.addLines(points.map { project($0.0, $0.1, $0.2) })
        path.closeSubpath()
        return path
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, seat: GraphicsContext.Shading, palette: Palette) {
        // Fill the frame, centred, cropping what overflows.
        let scale = max(size.width / width, size.height / height)
        context.translateBy(x: (size.width - width * scale) / 2, y: (size.height - height * scale) / 2)
        context.scaleBy(x: scale, y: scale)

        func fill(_ points: [(CGFloat, CGFloat, CGFloat)], _ colour: Color) {
            context.fill(polygon(points), with: .color(colour))
        }
        func fill(_ points: [(CGFloat, CGFloat, CGFloat)], _ shading: GraphicsContext.Shading, stroke width: CGFloat) {
            let path = polygon(points)
            context.fill(path, with: shading)
            context.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineJoin: .round))
        }

        // Floor and walls.
        fill([(-xw, 0, zw), (xw, 0, zw), (xw, 0, zn), (-xw, 0, zn)], palette.floor)
        fill([(-xw, 0, zw), (-xw, yw, zw), (-xw, yw, zn), (-xw, 0, zn)], palette.leftWall)
        fill([(xw, 0, zw), (xw, yw, zw), (xw, yw, zn), (xw, 0, zn)], palette.rightWall)
        for z0: CGFloat in [4.5, 8, 11.5] {
            let window = polygon([(-xw, 1.4, z0), (-xw, 3.2, z0), (-xw, 3.2, z0 + 2.2), (-xw, 1.4, z0 + 2.2)])
            context.fill(window, with: .color(palette.window))
            context.stroke(window, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }
        fill([(-xw, 0, zw), (xw, 0, zw), (xw, yw, zw), (-xw, yw, zw)], palette.backWall)

        // Blackboard, chalk and ledge.
        let bz = zw - 0.01
        fill([(-3.6, 1.0, bz), (3.6, 1.0, bz), (3.6, 2.8, bz), (-3.6, 2.8, bz)], palette.frame)
        fill([(-3.45, 1.1, bz), (3.45, 1.1, bz), (3.45, 2.7, bz), (-3.45, 2.7, bz)], palette.board)
        for (x1, y1, x2): (CGFloat, CGFloat, CGFloat) in [(-2.8, 2.35, -0.6), (-2.8, 2.05, 0.4), (-2.8, 1.75, -1.2),
                                                           (0.9, 2.3, 2.8), (0.9, 1.95, 2.2)] {
            var line = Path()
            line.move(to: project(x1, y1, bz))
            line.addLine(to: project(x2, y1, bz))
            context.stroke(line, with: .color(palette.chalk.opacity(0.8)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }
        fill([(-3.6, 1.0, bz - 0.15), (3.6, 1.0, bz - 0.15), (3.6, 1.0, bz), (-3.6, 1.0, bz)], palette.ledge)

        // Teacher's desk.
        let tz = zw - 1.6
        fill([(-1.4, 0.8, tz), (1.4, 0.8, tz), (1.4, 0.8, tz + 0.7), (-1.4, 0.8, tz + 0.7)], palette.deskTop)
        fill([(-1.4, 0.8, tz), (1.4, 0.8, tz), (1.4, 0, tz), (-1.4, 0, tz)], palette.deskFront)

        // Twelve rows of four seats each side of the aisle, the farthest first.
        let rows = 12, dz: CGFloat = 0.91, seatWidth: CGFloat = 0.78, gap: CGFloat = 0.16, x0: CGFloat = 0.62, n = 4
        let zFront = zw - 2.3
        for row in 0..<rows {
            let z = zFront - CGFloat(row) * dz
            for side: CGFloat in [-1, 1] {
                let xa = x0 - 0.1, xb = x0 + CGFloat(n) * seatWidth + CGFloat(n - 1) * gap + 0.1
                let (left, right) = side > 0 ? (xa, xb) : (-xb, -xa)
                let d0 = z + 0.12, d1 = z + 0.46
                let inner = side > 0 ? left : right
                fill([(inner, 0.78, d0), (inner, 0.78, d1), (inner, 0, d1), (inner, 0, d0)], palette.deskSide)
                fill([(left, 0.78, d0), (right, 0.78, d0), (right, 0.78, d1), (left, 0.78, d1)], palette.deskTop)
                fill([(left, 0.78, d0), (right, 0.78, d0), (right, 0.62, d0), (left, 0.62, d0)], palette.deskEdge)
                for j in 0..<n {
                    let a = x0 + CGFloat(j) * (seatWidth + gap), b = a + seatWidth
                    let (sa, sb) = side > 0 ? (a, b) : (-b, -a)
                    let stroke = 1.6 * f / z / 40
                    let zb = z - 0.45
                    fill([(sa, 1.16, zb), (sb, 1.16, zb), (sb, 1.16, zb + 0.1), (sa, 1.16, zb + 0.1)],
                         .color(palette.seatTop), stroke: stroke)
                    fill([(sa, 1.16, zb), (sb, 1.16, zb), (sb, 0.5, zb), (sa, 0.5, zb)], seat, stroke: stroke)
                }
            }
        }
    }
}

private extension Color {
    /// A colour from a 0xRRGGBB literal.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

#Preview {
    ClassroomSketch().frame(height: 193)
}
#endif

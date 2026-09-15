import SwiftUI

/// The material behind the Oggi page: a plain ground or a quiet pattern in
/// the look's colour, like the Lock Screen's wallpapers but kept faint so the
/// timetable stays readable.
nonisolated enum TodayBackground: String, Codable, CaseIterable, Identifiable, Sendable {
    case plain, wash, grid, dots, ovals, waves, stripes

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .plain: "Nessuno"
        case .wash: "Tinta"
        case .grid: "Griglia"
        case .dots: "Puntini"
        case .ovals: "Maglia ovale"
        case .waves: "Onde"
        case .stripes: "Righe"
        }
    }
}

/// Draws a ``TodayBackground`` in a colour. Patterns are drawn with `Canvas`,
/// so they stay sharp at any size and cost one layer.
struct TodayBackgroundView: View {
    let background: TodayBackground
    let tint: Color

    @Environment(\.colorScheme) private var scheme

    private var strength: Double { scheme == .dark ? 1.4 : 1 }

    var body: some View {
        ZStack {
            Color(.systemBackground)
            if background != .plain {
                tint.opacity(0.07 * strength)
            }
            pattern
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var pattern: some View {
        switch background {
        case .plain, .wash:
            EmptyView()
        case .grid:
            Canvas { context, size in
                let minor: CGFloat = 10, major: CGFloat = 100
                var fine = Path(), bold = Path()
                for x in stride(from: 0, through: size.width, by: minor) {
                    let line = Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }
                    x.truncatingRemainder(dividingBy: major) == 0 ? bold.addPath(line) : fine.addPath(line)
                }
                for y in stride(from: 0, through: size.height, by: minor) {
                    let line = Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }
                    y.truncatingRemainder(dividingBy: major) == 0 ? bold.addPath(line) : fine.addPath(line)
                }
                context.stroke(fine, with: .color(tint.opacity(0.10 * strength)), lineWidth: 0.5)
                context.stroke(bold, with: .color(tint.opacity(0.25 * strength)), lineWidth: 1)
            }
        case .dots:
            Canvas { context, size in
                let step: CGFloat = 16
                var dots = Path()
                for y in stride(from: step / 2, through: size.height, by: step) {
                    for x in stride(from: step / 2, through: size.width, by: step) {
                        dots.addEllipse(in: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8))
                    }
                }
                context.fill(dots, with: .color(tint.opacity(0.28 * strength)))
            }
        case .ovals:
            Canvas { context, size in
                let cell = CGSize(width: 34, height: 46)
                var ovals = Path()
                for (row, y) in stride(from: 0, through: size.height, by: cell.height).enumerated() {
                    let shift = row.isMultiple(of: 2) ? 0 : cell.width / 2
                    for x in stride(from: -cell.width, through: size.width, by: cell.width) {
                        ovals.addRoundedRect(in: CGRect(x: x + shift + 5, y: y + 5, width: cell.width - 10, height: cell.height - 10),
                                             cornerSize: CGSize(width: 12, height: 12))
                    }
                }
                context.stroke(ovals, with: .color(tint.opacity(0.22 * strength)), lineWidth: 1.5)
            }
        case .waves:
            Canvas { context, size in
                var waves = Path()
                for y in stride(from: CGFloat(0), through: size.height + 20, by: 22) {
                    waves.move(to: CGPoint(x: 0, y: y))
                    for x in stride(from: CGFloat(0), through: size.width, by: 4) {
                        waves.addLine(to: CGPoint(x: x, y: y + sin(x / 18) * 5))
                    }
                }
                context.stroke(waves, with: .color(tint.opacity(0.18 * strength)), lineWidth: 1.2)
            }
        case .stripes:
            Canvas { context, size in
                var stripes = Path()
                for x in stride(from: -size.height, through: size.width, by: 18) {
                    stripes.move(to: CGPoint(x: x, y: size.height))
                    stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                }
                context.stroke(stripes, with: .color(tint.opacity(0.12 * strength)), lineWidth: 5)
            }
        }
    }
}

#Preview("Sfondi") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 12) {
            ForEach(TodayBackground.allCases) { background in
                TodayBackgroundView(background: background, tint: .orange)
                    .frame(height: 180)
                    .clipShape(.rect(cornerRadius: 20))
                    .overlay(alignment: .bottomLeading) {
                        Text(background.title).font(.caption.weight(.semibold)).padding(8)
                    }
            }
        }
        .padding()
    }
}

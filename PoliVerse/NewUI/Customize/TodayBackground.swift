import SwiftUI

/// The material behind the Oggi page: a plain ground or a quiet pattern in
/// the look's colour, like the Lock Screen's wallpapers but kept faint so the
/// timetable stays readable.
nonisolated enum TodayBackground: String, Codable, CaseIterable, Identifiable, Sendable {
    case plain, wash, mesh, grid, dots, halftone, ovals, waves, stripes, zigzag, crosses, checker, hexagons, rings, confetti,
         study, science, maths, coding, space, nature, coffee, music, travel, sparkles

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
        case .mesh: "Sfumatura"
        case .halftone: "Retino"
        case .zigzag: "Zig-zag"
        case .crosses: "Croci"
        case .checker: "Scacchi"
        case .hexagons: "Esagoni"
        case .rings: "Cerchi"
        case .confetti: "Coriandoli"
        case .study: "Studio"
        case .science: "Scienze"
        case .maths: "Matematica"
        case .coding: "Codice"
        case .space: "Spazio"
        case .nature: "Natura"
        case .coffee: "Pausa caffè"
        case .music: "Musica"
        case .travel: "Viaggi"
        case .sparkles: "Scintille"
        }
    }

    /// The SF Symbols a symbol pattern repeats, in order; empty for the
    /// drawn patterns.
    var symbols: [String] {
        switch self {
        case .study: ["book.closed", "pencil", "graduationcap", "backpack", "books.vertical", "highlighter"]
        case .science: ["atom", "flask", "testtube.2", "microbe", "leaf", "bolt"]
        case .maths: ["function", "sum", "percent", "x.squareroot", "divide", "angle"]
        case .coding: ["chevron.left.forwardslash.chevron.right", "terminal", "curlybraces", "cpu", "number", "laptopcomputer"]
        case .space: ["moon.stars", "sparkle", "globe.europe.africa", "star", "circle.hexagongrid", "moon"]
        case .nature: ["leaf", "tree", "sun.max", "cloud", "drop", "camera.macro"]
        case .coffee: ["cup.and.saucer", "mug", "birthday.cake", "fork.knife", "takeoutbag.and.cup.and.straw", "carrot"]
        case .music: ["music.note", "headphones", "guitars", "music.quarternote.3", "pianokeys", "waveform"]
        case .travel: ["airplane", "map", "tram", "bicycle", "suitcase.rolling", "globe"]
        case .sparkles: ["sparkles", "star.fill", "sparkle", "heart", "seal", "wand.and.stars"]
        default: []
        }
    }
}

/// Draws a ``TodayBackground`` in a Flavor: its ground, with the pattern in
/// its accent. Patterns are drawn with `Canvas`, so they stay sharp at any
/// size and cost one layer. With no pattern the page keeps the system's
/// background.
struct TodayBackgroundView: View {
    let background: TodayBackground
    let flavor: Flavor
    var paper = TodayPaper.plain
    var grain = 0.0
    var mode = Flavor.Mode.standard
    /// Rounded here rather than by the caller: the grain shader rasterises the
    /// page, and a clip put around it afterwards does not reach the corners.
    var cornerRadius: CGFloat = 0

    @Environment(\.colorScheme) private var scheme

    /// A look's whole page: paper, decoration, grain, in its appearance.
    init(style: TodayStyle, cornerRadius: CGFloat = 0) {
        self.init(background: style.background, flavor: style.flavor, paper: style.paper, grain: style.grain,
                  mode: style.appearance.flavorMode, cornerRadius: cornerRadius)
    }

    init(background: TodayBackground, flavor: Flavor, paper: TodayPaper = .plain, grain: Double = 0,
         mode: Flavor.Mode = .standard, cornerRadius: CGFloat = 0) {
        self.background = background
        self.flavor = flavor
        self.paper = paper
        self.grain = grain
        self.mode = mode
        self.cornerRadius = cornerRadius
    }

    private var strength: Double { scheme == .dark ? 1.4 : 1 }
    private var tint: Color { flavor.accent(dark: scheme == .dark, mode: mode).color }

    var body: some View {
        page
            .paperGrain(grain)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var page: some View {
        // Rounded only when a card asks for it: the whole page draws faster
        // without a clip around its Canvas.
        if cornerRadius > 0 {
            ground.clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            ground
        }
    }

    private var ground: some View {
        ZStack {
            // The system's own background only for a page with nothing on it.
            if background == .plain && paper == .plain && mode == .standard {
                Color(.systemBackground)
            } else {
                flavor.ground(dark: scheme == .dark, mode: mode).color
            }
            paperTexture
            pattern
        }
    }

    @ViewBuilder
    private var paperTexture: some View {
        switch paper {
        case .plain:
            EmptyView()
        case .plot:
            // Millimetre paper: fine lines, a bolder line every five, and a
            // small cross where the bold ones meet.
            Canvas { context, size in
                let minor: CGFloat = 9, major = minor * 5
                var fine = Path(), bold = Path(), crosses = Path()
                for x in stride(from: 0, through: size.width, by: minor) {
                    let line = Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }
                    x.truncatingRemainder(dividingBy: major) == 0 ? bold.addPath(line) : fine.addPath(line)
                }
                for y in stride(from: 0, through: size.height, by: minor) {
                    let line = Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }
                    y.truncatingRemainder(dividingBy: major) == 0 ? bold.addPath(line) : fine.addPath(line)
                }
                for x in stride(from: 0, through: size.width, by: major) {
                    for y in stride(from: 0, through: size.height, by: major) {
                        crosses.move(to: CGPoint(x: x - 3, y: y)); crosses.addLine(to: CGPoint(x: x + 3, y: y))
                        crosses.move(to: CGPoint(x: x, y: y - 3)); crosses.addLine(to: CGPoint(x: x, y: y + 3))
                    }
                }
                context.stroke(fine, with: .color(tint.opacity(0.05 * strength)), lineWidth: 0.5)
                context.stroke(bold, with: .color(tint.opacity(0.1 * strength)), lineWidth: 0.8)
                context.stroke(crosses, with: .color(tint.opacity(0.3 * strength)), lineWidth: 1)
            }
        case .paper:
            // A warm sheet with fibres.
            tint.opacity(0.05 * strength)
                .colorEffect(ShaderLibrary.paperFibre(.float(0.12)))
        case .dots:
            Canvas { context, size in
                let step: CGFloat = 12
                var dots = Path()
                for y in stride(from: step / 2, through: size.height, by: step) {
                    for x in stride(from: step / 2, through: size.width, by: step) {
                        dots.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                    }
                }
                context.fill(dots, with: .color(tint.opacity(0.22 * strength)))
            }
        }
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
        case .mesh:
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                tint.opacity(0.30 * strength), .clear, tint.opacity(0.14 * strength),
                .clear, tint.opacity(0.18 * strength), .clear,
                tint.opacity(0.10 * strength), .clear, tint.opacity(0.26 * strength),
            ])
        case .halftone:
            // Dots that grow towards the top corner, like a printed gradient.
            Canvas { context, size in
                let step: CGFloat = 14
                var dots = Path()
                for y in stride(from: step / 2, through: size.height, by: step) {
                    for x in stride(from: step / 2, through: size.width, by: step) {
                        let reach = 1 - min(hypot(x, y) / hypot(size.width, size.height), 1)
                        let radius = 0.6 + 4.4 * reach * reach
                        dots.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    }
                }
                context.fill(dots, with: .color(tint.opacity(0.22 * strength)))
            }
        case .zigzag:
            Canvas { context, size in
                var zigzag = Path()
                for y in stride(from: CGFloat(0), through: size.height + 20, by: 24) {
                    zigzag.move(to: CGPoint(x: 0, y: y))
                    var up = true
                    for x in stride(from: CGFloat(10), through: size.width + 10, by: 10) {
                        zigzag.addLine(to: CGPoint(x: x, y: y + (up ? -6 : 0)))
                        up.toggle()
                    }
                }
                context.stroke(zigzag, with: .color(tint.opacity(0.18 * strength)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            }
        case .crosses:
            Canvas { context, size in
                let step: CGFloat = 28, arm: CGFloat = 4
                var crosses = Path()
                for (row, y) in stride(from: step / 2, through: size.height, by: step).enumerated() {
                    let shift = row.isMultiple(of: 2) ? 0 : step / 2
                    for x in stride(from: step / 2 - step, through: size.width, by: step) {
                        crosses.move(to: CGPoint(x: x + shift - arm, y: y)); crosses.addLine(to: CGPoint(x: x + shift + arm, y: y))
                        crosses.move(to: CGPoint(x: x + shift, y: y - arm)); crosses.addLine(to: CGPoint(x: x + shift, y: y + arm))
                    }
                }
                context.stroke(crosses, with: .color(tint.opacity(0.30 * strength)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        case .checker:
            Canvas { context, size in
                let cell: CGFloat = 24
                var squares = Path()
                for (row, y) in stride(from: CGFloat(0), through: size.height, by: cell).enumerated() {
                    for (column, x) in stride(from: CGFloat(0), through: size.width, by: cell).enumerated()
                    where (row + column).isMultiple(of: 2) {
                        squares.addRect(CGRect(x: x, y: y, width: cell, height: cell))
                    }
                }
                context.fill(squares, with: .color(tint.opacity(0.07 * strength)))
            }
        case .hexagons:
            Canvas { context, size in
                let radius: CGFloat = 16
                let width = radius * sqrt(3), rowHeight = radius * 1.5
                var hexagons = Path()
                for (row, y) in stride(from: CGFloat(0), through: size.height + radius, by: rowHeight).enumerated() {
                    let shift = row.isMultiple(of: 2) ? 0 : width / 2
                    for x in stride(from: -width, through: size.width + width, by: width) {
                        let center = CGPoint(x: x + shift, y: y)
                        for corner in 0...6 {
                            let angle = CGFloat(corner) * .pi / 3 + .pi / 6
                            let point = CGPoint(x: center.x + (radius - 2) * cos(angle), y: center.y + (radius - 2) * sin(angle))
                            corner == 0 ? hexagons.move(to: point) : hexagons.addLine(to: point)
                        }
                    }
                }
                context.stroke(hexagons, with: .color(tint.opacity(0.2 * strength)), lineWidth: 1.2)
            }
        case .rings:
            // Rings spreading from the top corner, like a ripple.
            Canvas { context, size in
                var rings = Path()
                let origin = CGPoint(x: size.width, y: 0)
                for radius in stride(from: CGFloat(30), through: hypot(size.width, size.height), by: 26) {
                    rings.addEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
                }
                context.stroke(rings, with: .color(tint.opacity(0.16 * strength)), lineWidth: 1.5)
            }
        case .study, .science, .maths, .coding, .space, .nature, .coffee, .music, .travel, .sparkles:
            SymbolPattern(symbols: background.symbols, tint: tint.opacity(0.22 * strength))
        case .confetti:
            Canvas { context, size in
                // A fixed sequence, so the confetti does not move between draws.
                var generator = SeededGenerator(seed: 7)
                let count = Int(size.width * size.height / 1400)
                for _ in 0..<count {
                    let point = CGPoint(x: .random(in: 0...size.width, using: &generator),
                                        y: .random(in: 0...size.height, using: &generator))
                    let angle = Angle.degrees(.random(in: 0...180, using: &generator))
                    var piece = context
                    piece.translateBy(x: point.x, y: point.y)
                    piece.rotate(by: angle)
                    let shape = Int.random(in: 0...2, using: &generator)
                    let path: Path = switch shape {
                    case 0: Path(roundedRect: CGRect(x: -5, y: -1.5, width: 10, height: 3), cornerRadius: 1.5)
                    case 1: Path(ellipseIn: CGRect(x: -2.5, y: -2.5, width: 5, height: 5))
                    default: Path { $0.move(to: CGPoint(x: 0, y: -4)); $0.addLine(to: CGPoint(x: 4, y: 3)); $0.addLine(to: CGPoint(x: -4, y: 3)); $0.closeSubpath() }
                    }
                    piece.fill(path, with: .color(tint.opacity(Double.random(in: 0.15...0.35, using: &generator) * strength)))
                }
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

/// SF Symbols scattered on a staggered grid, each a little turned and sized
/// differently, so the pattern reads as drawn by hand rather than stamped.
private struct SymbolPattern: View {
    let symbols: [String]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 54
            var generator = SeededGenerator(seed: UInt64(symbols.joined().count))
            for (row, y) in stride(from: CGFloat(0), through: size.height + cell, by: cell).enumerated() {
                let shift = row.isMultiple(of: 2) ? 0 : cell / 2
                for (column, x) in stride(from: -cell, through: size.width + cell, by: cell).enumerated() {
                    let index = (row * 2 + column) % symbols.count
                    guard let symbol = context.resolveSymbol(id: index) else { continue }
                    var piece = context
                    piece.translateBy(x: x + shift + .random(in: -6...6, using: &generator),
                                      y: y + .random(in: -6...6, using: &generator))
                    piece.rotate(by: .degrees(.random(in: -18...18, using: &generator)))
                    let scale = CGFloat.random(in: 0.8...1.15, using: &generator)
                    piece.scaleBy(x: scale, y: scale)
                    piece.draw(symbol, at: .zero)
                }
            }
        } symbols: {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, name in
                Image(systemName: name)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tint)
                    .tag(index)
            }
        }
    }
}

/// A small deterministic random source (SplitMix64) for patterns that must
/// look scattered but draw the same every time.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview("Sfondi") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 12) {
            ForEach(TodayBackground.allCases) { background in
                TodayBackgroundView(background: background, flavor: Flavor(hex: "#E8751A")!)
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

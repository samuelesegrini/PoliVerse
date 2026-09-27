import SwiftUI

/// Where a tool is drawn: one row that scrolls sideways under the page on
/// iPhone, or a grid in the inspector on iPad and Mac.
enum ToolLayout: Equatable {
    /// A row under the page, scrolling sideways.
    case strip
    /// A grid in the inspector.
    case inspector
}

extension View {
    /// The ring around a chosen tile, card or swatch: a gap, then white. An
    /// unchosen one gets a faint edge instead, so it reads on black.
    ///
    /// - Parameters:
    ///   - chosen: Whether it is the one in use.
    ///   - shape: Its outline.
    /// - Returns: The view, ringed.
    func chosenRing<S: InsettableShape>(_ chosen: Bool, in shape: S) -> some View {
        overlay {
            if chosen {
                shape.inset(by: -3.5).strokeBorder(.white, lineWidth: 2)
            } else {
                shape.strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }
}

/// A tool's choices: a row that scrolls sideways, or a grid.
struct ToolRow<Content: View>: View {
    /// Where the tool is drawn.
    let layout: ToolLayout
    /// A grid cell's narrowest width.
    var minimum: CGFloat = 66
    /// Space between the choices.
    var spacing: CGFloat = 8
    /// The choices.
    @ViewBuilder let content: () -> Content

    /// The view's content.
    var body: some View {
        switch layout {
        case .strip:
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: spacing) { content() }
                    // Room for the ring round the first and last.
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        case .inspector:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .top)],
                      alignment: .leading, spacing: 14) {
                content()
            }
            .padding(.vertical, 6)
        }
    }
}

/// One choice drawn as a small square: a paper, a pattern, a typeface, a
/// surface. Its name under it.
struct ToolTile<Face: View>: View {
    /// What it is called.
    let title: Text
    /// Whether it is the one in use.
    let chosen: Bool
    /// Chooses it.
    let action: () -> Void
    /// What the square shows.
    @ViewBuilder let face: () -> Face

    /// The view's content.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                face()
                    .frame(width: 58, height: 58)
                    .clipShape(shape)
                    .chosenRing(chosen, in: shape)
                title
                    .font(.caption)
                    .foregroundStyle(chosen ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 66)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// One choice as a capsule: white when chosen, with a dot of colour when it has one.
struct ToolChip: View {
    /// What it is called.
    let title: Text
    /// A dot of what it looks like, if anything.
    var dot: AnyShapeStyle?
    /// Whether it is the one in use.
    let chosen: Bool
    /// Chooses it.
    let action: () -> Void

    /// The view's content.
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 16, height: 16)
                        .overlay { Circle().strokeBorder(.gray.opacity(0.45), lineWidth: 1) }
                }
                title
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .padding(.leading, dot == nil ? 18 : 14)
            .padding(.trailing, 18)
            .frame(minHeight: 40)
            .foregroundStyle(chosen ? Color.black : .white)
            .background(chosen ? Color.white : Color(white: 0.11), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A row of chips: sideways on iPhone, wrapping in the inspector.
struct ChipRow<Content: View>: View {
    /// Where the tool is drawn.
    let layout: ToolLayout
    /// The chips.
    @ViewBuilder let content: () -> Content

    /// The view's content.
    var body: some View {
        switch layout {
        case .strip:
            ScrollView(.horizontal) {
                HStack(spacing: 10) { content() }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        case .inspector:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                content()
            }
        }
    }
}

/// A value on a ruler: its name and value above, ticks that slide under a
/// fixed line as it is dragged, and − and + either side, as the Camera's
/// dials do. Adjustable with VoiceOver.
struct ToolRuler: View {
    /// What the value is.
    let title: LocalizedStringKey
    /// The value, in the ruler's own units.
    @Binding var value: Double
    /// Its range.
    let range: ClosedRange<Double>
    /// How far a tick, a button or a swipe moves it.
    let step: Double
    /// What follows the number: "%" or nothing.
    var unit = ""

    /// Where the value was when the drag began.
    @State private var dragStart: Double?

    /// The ticks' spacing.
    private static let spacing: CGFloat = 9
    /// How many ticks span the range.
    private static let ticks = 40

    /// The value as it reads.
    private var label: String { "\(Int(value.rounded()))\(unit)" }

    /// The view's content.
    var body: some View {
        HStack(spacing: 10) {
            nudge("minus", by: -step)
                .accessibilityLabel(Text("Meno"))
            ZStack(alignment: .top) {
                HStack(spacing: 4) {
                    Text(title).foregroundStyle(.secondary)
                    Text(verbatim: label).fontWeight(.semibold)
                }
                .font(.footnote)
                .monospacedDigit()
                Canvas { context, size in
                    let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                    let centre = size.width / 2
                    for index in 0...Self.ticks {
                        let x = centre + (CGFloat(index) / CGFloat(Self.ticks) - fraction) * CGFloat(Self.ticks) * Self.spacing
                        let major = index % 5 == 0
                        let rect = CGRect(x: x - 1, y: 30, width: 2, height: major ? 18 : 10)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1),
                                     with: .color(major ? Color(white: 0.56) : Color(white: 0.28)))
                    }
                    let line = CGRect(x: centre - 1.5, y: 25, width: 3, height: 30)
                    context.fill(Path(roundedRect: line, cornerRadius: 1.5), with: .color(.white))
                }
            }
            .frame(width: 250, height: 62)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                       .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        dragStart = start
                        let span = range.upperBound - range.lowerBound
                        set(start - Double(drag.translation.width) / Double(CGFloat(Self.ticks) * Self.spacing) * span)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            nudge("plus", by: step)
                .accessibilityLabel(Text("Più"))
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: label))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + step)
            case .decrement: set(value - step)
            @unknown default: break
            }
        }
    }

    /// One of the round − and + buttons.
    private func nudge(_ symbol: String, by amount: Double) -> some View {
        Button { set(value + amount) } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.1), in: .circle)
        }
        .buttonStyle(.plain)
    }

    /// Sets the value, snapped to a step and kept in range.
    private func set(_ new: Double) {
        let snapped = ((new - range.lowerBound) / step).rounded() * step + range.lowerBound
        let clamped = snapped.clamped(to: range)
        if clamped != value { value = clamped }
    }
}

extension Flavor.RGB {
    /// This colour a share of the way to another.
    ///
    /// - Parameters:
    ///   - other: The colour to move towards.
    ///   - amount: How far, from 0 to 1.
    /// - Returns: The mixed colour.
    func mixed(with other: Flavor.RGB, _ amount: Double) -> Flavor.RGB {
        Flavor.RGB(red: red + (other.red - red) * amount,
                   green: green + (other.green - green) * amount,
                   blue: blue + (other.blue - blue) * amount)
    }

    /// A colour from hue, saturation and lightness, as the colour grid lays them out.
    ///
    /// - Parameters:
    ///   - hue: Degrees round the wheel.
    ///   - saturation: From 0 to 1.
    ///   - lightness: From 0 to 1.
    init(hue: Double, saturation: Double, lightness: Double) {
        let amount = saturation * min(lightness, 1 - lightness)
        func channel(_ n: Double) -> Double {
            let k = (n + hue / 30).truncatingRemainder(dividingBy: 12)
            return lightness - amount * max(-1, min(k - 3, min(9 - k, 1)))
        }
        self.init(red: channel(0), green: channel(8), blue: channel(4))
    }
}

/// A colour to pick, drawn as a cone: lighter and darker round its edge, so
/// it reads as a colour rather than a flat dot.
struct ConeSwatch: View {
    /// The colour.
    let colour: Flavor.RGB
    /// Its side.
    var side: CGFloat = 48

    /// The view's content.
    var body: some View {
        let light = colour.mixed(with: .white, 0.55).color
        let dark = colour.mixed(with: .black, 0.45).color
        let base = colour.color
        Circle()
            .fill(AngularGradient(colors: [light, base, dark, base, light], center: .center,
                                  startAngle: .degrees(110), endAngle: .degrees(470)))
            .frame(width: side, height: side)
    }
}

/// The swatches, a line, and Altri colori, which opens the grid of every colour.
struct SwatchRow: View {
    /// Where the tool is drawn.
    let layout: ToolLayout
    /// The colour in use, if it is one of the choices; `nil` for Automatico.
    let current: Flavor.RGB?
    /// What the grid's sheet is called.
    let gridTitle: LocalizedStringKey
    /// Chooses a colour.
    let pick: (Flavor.RGB) -> Void
    /// Automatico, first, where the colour can follow another.
    var automatic: (colour: Flavor.RGB, chosen: Bool, pick: () -> Void)?

    @State private var showsGrid = false

    /// The view's content.
    var body: some View {
        Group {
            switch layout {
            case .strip:
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        if let automatic {
                            automaticButton(automatic)
                            divider
                        }
                        swatches
                        divider
                        more
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 84)
                }
                .scrollIndicators(.hidden)
            case .inspector:
                VStack(alignment: .leading, spacing: 12) {
                    if let automatic { automaticButton(automatic) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                        swatches
                        more
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $showsGrid) {
            ColourGridSheet(title: gridTitle, current: current, pick: pick)
        }
    }

    /// The Flavor swatches.
    private var swatches: some View {
        ForEach(Flavor.swatches) { swatch in
            let chosen = current?.hex == swatch.flavor.base.hex
            Button { pick(swatch.flavor.base) } label: {
                ConeSwatch(colour: swatch.flavor.base, side: layout == .strip ? 48 : 40)
                    .chosenRing(chosen, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(swatch.name))
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityIdentifier("swatch-\(swatch.flavor.hex)")
        }
    }

    /// Altri colori: a wheel with a plus, opening the grid.
    private var more: some View {
        Button { showsGrid = true } label: {
            Circle()
                .fill(AngularGradient(colors: [Color(red: 0.88, green: 0.35, blue: 0.31), .orange, .yellow, .green, .cyan, .indigo, .pink,
                                               Color(red: 0.88, green: 0.35, blue: 0.31)], center: .center))
                .frame(width: layout == .strip ? 48 : 40, height: layout == .strip ? 48 : 40)
                .overlay {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color(white: 0.11), in: .circle)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Altri colori"))
        .accessibilityIdentifier("swatch-more")
    }

    /// Automatico: the colour it would follow, ringed while chosen.
    private func automaticButton(_ automatic: (colour: Flavor.RGB, chosen: Bool, pick: () -> Void)) -> some View {
        Button(action: automatic.pick) {
            HStack(spacing: 8) {
                ConeSwatch(colour: automatic.colour, side: 32)
                Text("Automatico")
                    .font(.subheadline)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .frame(height: 48)
            .background(Color(white: 0.17), in: .capsule)
            .chosenRing(automatic.chosen, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Automatico: segue il Flavor"))
        .accessibilityAddTraits(automatic.chosen ? .isSelected : [])
        .accessibilityIdentifier("swatch-automatic")
    }

    /// The thin line between groups of swatches.
    private var divider: some View {
        Rectangle()
            .fill(Color(white: 0.23))
            .frame(width: 1, height: 36)
    }
}

/// Every colour at once: eleven hues from light to dark, and a column of
/// greys, as the system's colour picker lays its grid out.
struct ColourGridSheet: View {
    /// What the colour is for.
    let title: LocalizedStringKey
    /// The colour in use, ringed if it is in the grid.
    let current: Flavor.RGB?
    /// Chooses a colour.
    let pick: (Flavor.RGB) -> Void

    /// Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    /// The hues across, in degrees.
    private static let hues: [Double] = [0, 20, 38, 52, 90, 140, 172, 198, 222, 262, 300]
    /// The lightness of each row, from light to dark.
    private static let lights: [Double] = [0.86, 0.76, 0.66, 0.56, 0.46, 0.36, 0.27, 0.18]

    /// The colour at one place in the grid.
    private static func colour(row: Int, column: Int) -> Flavor.RGB {
        if column == hues.count {
            return Flavor.RGB(hue: 0, saturation: 0, lightness: 0.96 - Double(row) * 0.12)
        }
        return Flavor.RGB(hue: hues[column], saturation: 0.78, lightness: lights[row])
    }

    /// The view's content.
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Griglia")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Self.lights.indices, id: \.self) { row in
                        GridRow {
                            ForEach(0...Self.hues.count, id: \.self) { column in
                                let colour = Self.colour(row: row, column: column)
                                let chosen = current?.hex == colour.hex
                                Button {
                                    pick(colour)
                                    dismiss()
                                } label: {
                                    Rectangle()
                                        .fill(colour.color)
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay {
                                            if chosen {
                                                Rectangle().strokeBorder(.white, lineWidth: 3)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Colore \(column + 1), riga \(row + 1)"))
                            }
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .environment(\.colorScheme, .dark)
    }
}

/// One choice drawn as the top of the page it makes: a greeting, or what
/// sits beside the date. Its name under it.
struct PageCard<Face: View>: View {
    /// The look the card is drawn in.
    let look: TodayStyle
    /// What it is called.
    let title: Text
    /// Whether it is the one in use.
    let chosen: Bool
    /// Chooses it.
    let action: () -> Void
    /// What the card shows on the page.
    @ViewBuilder let face: () -> Face

    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let drawn = look.resolved
        let lit = drawn.appearance.colorScheme ?? scheme
        Button(action: action) {
            VStack(spacing: 7) {
                face()
                    .padding(10)
                    .frame(width: 92, height: 96, alignment: .topLeading)
                    .background { TodayBackgroundView(style: drawn) }
                    .environment(\.colorScheme, lit)
                    .clipShape(shape)
                    .chosenRing(chosen, in: shape)
                title
                    .font(.caption.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 96)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A tool's name over its controls, as the inspector stacks them.
struct ToolGroup<Content: View>: View {
    /// What the group is called; none for a group that follows on from the one above.
    let title: LocalizedStringKey?
    /// A line under the controls.
    var note: LocalizedStringKey?
    /// The controls.
    @ViewBuilder let content: () -> Content

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

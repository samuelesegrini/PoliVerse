import SwiftUI

// The first run's own small design language, drawn from one idea: the journey is
// a card over a landscape, and three looks say everything a control needs to.
//
// - Cream glass is what is chosen, or yours.
// - A dashed outline, in ink that takes the colour of the landscape behind it,
//   is what is offered and not taken.
// - Blue is the one gesture on a screen.

// MARK: - Ink

/// The journey's colours. Few on purpose: the landscape supplies the rest.
enum JourneyInk {
    /// The glass of whatever is chosen.
    static let cream = Color(red: 1, green: 0.984, blue: 0.94)
    /// Text on cream.
    static let ink = Color(red: 0.184, green: 0.2, blue: 0.133)
    /// Secondary text on cream.
    static let inkSoft = Color(red: 0.373, green: 0.384, blue: 0.314)
    /// The one action on a screen, and a choice being on.
    static let action = Color(red: 0.122, green: 0.486, blue: 0.949)
    /// Grey that, multiplied over the landscape, reads as a darker shade of it.
    static let vibrant = Color(white: 0.37)
    /// The same, for filled discs.
    static let vibrantDisc = Color(white: 0.49)
}

// MARK: - Landscape

/// The colours of one landscape: a sky, a horizon, a ground and a few patches that
/// keep it from reading as a gradient.
nonisolated struct JourneyPalette: Equatable, Sendable {
    /// The top of the sky.
    var sky: Flavor.RGB
    /// The light in the sky.
    var skylight: Flavor.RGB
    /// Where sky meets ground.
    var horizon: Flavor.RGB
    /// A warm patch: flowers, a sunset.
    var accent: Flavor.RGB
    /// The ground.
    var ground: Flavor.RGB
    /// The ground in the light.
    var groundlight: Flavor.RGB
    /// Dark patches: foliage, shade.
    var spot: Flavor.RGB

    /// The colours in the order a 3 × 4 mesh reads them, row by row.
    var mesh: [Flavor.RGB] {
        [sky, sky, skylight,
         accent, skylight, horizon,
         spot, horizon, accent,
         groundlight, ground, spot]
    }

    /// Part of the way from this palette to another.
    ///
    /// - Parameters:
    ///   - other: Where to go.
    ///   - amount: 0 is this palette, 1 is `other`.
    /// - Returns: The palette in between.
    func mixed(with other: JourneyPalette, _ amount: Double) -> JourneyPalette {
        func mix(_ a: Flavor.RGB, _ b: Flavor.RGB) -> Flavor.RGB { a.blended(with: b, amount) }
        return JourneyPalette(
            sky: mix(sky, other.sky), skylight: mix(skylight, other.skylight),
            horizon: mix(horizon, other.horizon), accent: mix(accent, other.accent),
            ground: mix(ground, other.ground), groundlight: mix(groundlight, other.groundlight),
            spot: mix(spot, other.spot))
    }

    /// Builds a palette from seven hex colours, in the order of the properties.
    private init(_ hexes: [String]) {
        let rgb = hexes.map { Flavor.RGB(hex: $0)! }
        self.init(sky: rgb[0], skylight: rgb[1], horizon: rgb[2], accent: rgb[3],
                  ground: rgb[4], groundlight: rgb[5], spot: rgb[6])
    }

    /// Memberwise.
    init(sky: Flavor.RGB, skylight: Flavor.RGB, horizon: Flavor.RGB, accent: Flavor.RGB,
         ground: Flavor.RGB, groundlight: Flavor.RGB, spot: Flavor.RGB) {
        self.sky = sky
        self.skylight = skylight
        self.horizon = horizon
        self.accent = accent
        self.ground = ground
        self.groundlight = groundlight
        self.spot = spot
    }

    /// The welcome: early light.
    static let dawn = JourneyPalette(["#6D87D4", "#A9B9EF", "#E9B3C4", "#F3B48F", "#D99AB3", "#F5CFA6", "#8E79C9"])
    /// The questions: a spring meadow.
    static let meadow = JourneyPalette(["#5E98D6", "#A8CDEE", "#D9B7D6", "#E7AAD6", "#8AA846", "#BCCD72", "#5F7F37"])
    /// The account: a lake, calmer.
    static let lake = JourneyPalette(["#5B7CCC", "#9FB4EC", "#B9B3E6", "#D2A9E0", "#6F8FD2", "#A8C4EE", "#4A64B0"])
    /// The reminders: evening.
    static let sunset = JourneyPalette(["#8474CC", "#B8A2E4", "#EEA88F", "#F5C58C", "#DF8DA3", "#F3B98F", "#7A58A6"])

    /// A landscape in a Flavor's colour, for the end of the journey.
    ///
    /// Very dark colours are lifted first: the ink multiplies over the landscape, and
    /// over near-black it would disappear.
    ///
    /// - Parameter flavor: The Flavor chosen.
    /// - Returns: Its landscape.
    static func flavor(_ flavor: Flavor) -> JourneyPalette {
        var base = flavor.base
        if base.luminance < 0.06 { base = base.blended(with: .white, 0.32) }
        let blush = Flavor.RGB(hex: "#F2B8C6")!
        return JourneyPalette(
            sky: base.blended(with: .black, 0.1),
            skylight: base.blended(with: .white, 0.45),
            horizon: base.blended(with: .white, 0.62),
            accent: base.blended(with: blush, 0.45),
            ground: base,
            groundlight: base.blended(with: .white, 0.3),
            spot: base.blended(with: .black, 0.3))
    }
}

nonisolated extension Flavor.RGB {
    /// Part of the way to another colour, channel by channel.
    ///
    /// - Parameters:
    ///   - other: Where to go.
    ///   - amount: 0 is this colour, 1 is `other`.
    /// - Returns: The colour in between.
    func blended(with other: Flavor.RGB, _ amount: Double) -> Flavor.RGB {
        Flavor.RGB(red: red + (other.red - red) * amount,
                   green: green + (other.green - green) * amount,
                   blue: blue + (other.blue - blue) * amount)
    }
}

/// The landscape behind every step: a mesh that drifts slowly, and crosses over to
/// the next step's colours rather than cutting to them, so the journey reads as one
/// day passing — dawn, meadow, lake, evening, then the colour the student chose.
struct JourneyLandscape: View {
    /// The colours to show, or to cross over to.
    let palette: JourneyPalette

    /// The colours being left, while crossing over.
    @State private var leaving: JourneyPalette?
    /// When the last crossing began.
    @State private var changedAt = Date.distantPast
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long a crossing takes.
    private let crossing: TimeInterval = 1.6

    /// The view's content.
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            MeshGradient(
                width: 3, height: 4,
                points: points(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate),
                colors: shown(at: context.date, heading: palette).mesh.map(\.color))
        }
        .onChange(of: palette) { old, _ in
            // From what is on screen, not from the old target: a second change
            // mid-crossing — two quick taps on the atmosphere step — carries on
            // from the colours showing instead of snapping back.
            leaving = shown(at: .now, heading: old)
            changedAt = reduceMotion ? .distantPast : .now
        }
        .accessibilityHidden(true)
    }

    /// The colours showing at a moment, part of the way from ``leaving`` to a target.
    ///
    /// - Parameters:
    ///   - date: The moment.
    ///   - target: Where the crossing is heading.
    /// - Returns: The palette on screen.
    private func shown(at date: Date, heading target: JourneyPalette) -> JourneyPalette {
        guard let leaving else { return target }
        let progress = min(max(date.timeIntervalSince(changedAt) / crossing, 0), 1)
        // Ease in and out: a crossing that starts and stops at full speed reads
        // as a cut with a smear.
        let eased = progress * progress * (3 - 2 * progress)
        return leaving.mixed(with: target, eased)
    }

    /// The mesh's points, the inner ones wandering on slow sines so the landscape
    /// breathes without anything in it visibly moving.
    ///
    /// - Parameter time: Seconds, from any fixed origin.
    /// - Returns: Twelve points, row by row.
    private func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func wander(_ phase: Double, _ amount: Double) -> Float { Float(sin(time * 0.22 + phase) * amount) }
        return [
            [0, 0], [0.5 + wander(0, 0.08), 0], [1, 0],
            [0, 0.34 + wander(1, 0.05)], [0.5 + wander(2, 0.1), 0.36 + wander(3, 0.06)], [1, 0.3 + wander(4, 0.05)],
            [0, 0.66 + wander(5, 0.05)], [0.5 + wander(6, 0.1), 0.64 + wander(7, 0.06)], [1, 0.7 + wander(8, 0.05)],
            [0, 1], [0.5 + wander(9, 0.08), 1], [1, 1],
        ]
    }
}

// MARK: - Surfaces

extension View {
    /// Ink that takes the colour of the landscape behind it: a grey multiplied over
    /// it, so over a meadow it reads olive and over a sunset, plum.
    ///
    /// Solid and dark instead when the reader has asked for less transparency.
    func journeyVibrant() -> some View { modifier(JourneyVibrancy()) }

    /// Cream glass behind a capsule: what is chosen, or yours.
    func journeyCream() -> some View { modifier(JourneyCreamGlass()) }

    /// A dashed outline in landscape ink: offered, not taken.
    ///
    /// - Parameter visible: Whether it shows, so it can fade rather than pop.
    func journeyDashed(_ visible: Bool = true) -> some View {
        background {
            Capsule()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.6, dash: [8, 7]))
                .journeyVibrant()
                .opacity(visible ? 1 : 0)
        }
    }
}

/// See ``SwiftUICore/View/journeyVibrant()``.
private struct JourneyVibrancy: ViewModifier {
    /// Whether the reader has asked for less transparency.
    @Environment(\.accessibilityReduceTransparency) private var solid

    /// The modified content.
    func body(content: Content) -> some View {
        if solid {
            content.foregroundStyle(Color.black.opacity(0.72))
        } else {
            content.foregroundStyle(JourneyInk.vibrant).blendMode(.multiply)
        }
    }
}

/// See ``SwiftUICore/View/journeyCream()``.
private struct JourneyCreamGlass: ViewModifier {
    /// Whether the reader has asked for less transparency.
    @Environment(\.accessibilityReduceTransparency) private var solid

    /// The modified content.
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if !solid { Capsule().fill(.ultraThinMaterial) }
                Capsule().fill(JourneyInk.cream.opacity(solid ? 1 : 0.84))
            }
            .shadow(color: Color(red: 0.12, green: 0.16, blue: 0.08).opacity(0.14), radius: 14, y: 10)
        }
    }
}

// MARK: - Avatars

/// A round avatar holding a real fragment of the thing it stands for — 10:15 for the
/// timetable, 30L for the exams — where the reference had faces.
struct JourneyAvatar: View {
    /// What is drawn inside.
    enum Mark: Equatable {
        /// A short text, at a fraction of the side.
        case text(String, scale: CGFloat)
        /// An SF Symbol.
        case symbol(String)
        /// Colour alone.
        case none
    }

    /// What is drawn inside.
    let mark: Mark
    /// The light and dark ends of the disc's gradient.
    let colours: (light: Color, dark: Color)
    /// The diameter.
    var side: CGFloat = 50

    /// The view's content.
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [colours.light, colours.dark],
                                 center: UnitPoint(x: 0.32, y: 0.26),
                                 startRadius: 0, endRadius: side * 0.8))
            .overlay {
                switch mark {
                case .text(let text, let scale):
                    Text(verbatim: text)
                        .font(.system(size: side * scale, weight: .heavy, design: .rounded))
                        .tracking(-0.4)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: side * 0.36, weight: .bold))
                case .none:
                    EmptyView()
                }
            }
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.22), radius: 6, y: 4)
            .accessibilityHidden(true)
    }
}

extension JourneyFlow.Intent {
    /// The pill's words, capitalised on the noun the way the reference does.
    var title: LocalizedStringResource {
        switch self {
        case .timetable: "per l'Orario"
        case .exams: "per gli Esami"
        case .recordings: "per i Video"
        case .rooms: "per le Aule"
        case .average: "per la Media"
        case .everything: "Boh… per Tutto"
        }
    }

    /// The fragment in the avatar.
    var mark: JourneyAvatar.Mark {
        switch self {
        case .timetable: .text("10:15", scale: 0.28)
        case .exams: .text("30L", scale: 0.32)
        case .recordings: .symbol("play.fill")
        case .rooms: .text("B.2", scale: 0.32)
        case .average: .text("27,4", scale: 0.28)
        case .everything: .text("?", scale: 0.48)
        }
    }

    /// The avatar's colours.
    var colours: (light: Color, dark: Color) {
        let pair: (String, String) = switch self {
        case .timetable: ("#7FA6F0", "#3565C9")
        case .exams: ("#F39A7E", "#CF4A36")
        case .recordings: ("#A98CF0", "#6A45C4")
        case .rooms: ("#77CF9F", "#268A5B")
        case .average: ("#F3C35E", "#C1830E")
        case .everything: ("#F28BB4", "#BF3470")
        }
        return (Flavor.RGB(hex: pair.0)!.color, Flavor.RGB(hex: pair.1)!.color)
    }

    /// The avatar, at a given size.
    ///
    /// - Parameter side: The diameter.
    /// - Returns: The avatar.
    func avatar(side: CGFloat = 50) -> JourneyAvatar {
        JourneyAvatar(mark: mark, colours: colours, side: side)
    }
}

// MARK: - Titles

/// Marks the word a title underlines by hand.
struct HandMark: TextAttribute {}

/// Draws a title, and a hand-drawn stroke under each run marked ``HandMark``, drawn
/// in as `progress` goes from 0 to 1.
struct HandUnderline: TextRenderer, Animatable {
    /// How much of the stroke is drawn.
    var progress: Double

    /// What SwiftUI animates.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Draws the text, then the strokes.
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                context.draw(run)
                guard run[HandMark.self] != nil, progress > 0 else { continue }
                let bounds = run.typographicBounds
                let rect = bounds.rect
                let y = bounds.origin.y + bounds.descent * 0.55
                var stroke = Path()
                stroke.move(to: CGPoint(x: rect.minX + 2, y: y + 3))
                stroke.addCurve(to: CGPoint(x: rect.maxX - 2, y: y + 1),
                                control1: CGPoint(x: rect.minX + rect.width * 0.3, y: y - 1),
                                control2: CGPoint(x: rect.minX + rect.width * 0.7, y: y - 2))
                context.stroke(stroke.trimmedPath(from: 0, to: progress),
                               with: .color(.white.opacity(0.96)),
                               style: StrokeStyle(lineWidth: max(3, rect.height * 0.08), lineCap: .round))
            }
        }
    }
}

/// A step's title: big, rounded, white, one word underlined by hand.
///
/// The underlined word is marked in the string itself with Markdown emphasis —
/// `"A cosa ti _serve_ PoliVerse?"` — so a translation moves the mark with the word.
struct JourneyTitle: View {
    /// The title, with its marked word in `_emphasis_`.
    let resource: LocalizedStringResource

    /// Whether the title has come in.
    @State private var shown = false
    /// How much of the underline is drawn.
    @State private var drawn = 0.0
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The view's content.
    var body: some View {
        Self.text(resource)
            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
            .tracking(-0.8)
            .foregroundStyle(.white.opacity(0.96))
            .multilineTextAlignment(.center)
            .shadow(color: Color(red: 0.12, green: 0.16, blue: 0.31).opacity(0.18), radius: 11, y: 2)
            .textRenderer(HandUnderline(progress: drawn))
            .blur(radius: shown || reduceMotion ? 0 : 10)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .opacity(shown ? 1 : 0)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.8)) { shown = true }
                withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.6).delay(reduceMotion ? 0 : 0.5)) { drawn = 1 }
            }
    }

    /// The title as text, the emphasised run carrying ``HandMark`` instead of italics.
    ///
    /// - Parameter resource: The localised title.
    /// - Returns: The text.
    static func text(_ resource: LocalizedStringResource) -> Text {
        let attributed = AttributedString(localized: resource)
        return attributed.runs.reduce(Text(verbatim: "")) { text, run in
            let piece = Text(verbatim: String(attributed[run.range].characters))
            let marked = run.inlinePresentationIntent?.contains(.emphasized) == true
            return Text("\(text)\(marked ? piece.customAttribute(HandMark()) : piece)")
        }
    }
}

// MARK: - Controls

/// Shrinks a little under the finger and springs back.
struct JourneyPress: ButtonStyle {
    /// The styled button.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// The one action on a step: a cream capsule ending in a blue disc.
struct JourneyAction: View {
    /// What it says.
    let title: LocalizedStringKey
    /// The symbol in the disc.
    var symbol = "arrow.right"
    /// The disc's colour.
    var disc = JourneyInk.action
    /// Whether it is working, which swaps the symbol for a spinner.
    var isBusy = false
    /// What it does.
    let action: () -> Void

    /// The view's content.
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .tracking(-0.4)
                    .padding(.leading, 20)
                ZStack {
                    Circle().fill(disc)
                    if isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: symbol)
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .padding(6)
            .foregroundStyle(JourneyInk.ink)
            .journeyCream()
        }
        .buttonStyle(JourneyPress())
        .disabled(isBusy)
        .accessibilityIdentifier("onboarding-primary")
    }
}

/// A quiet way out, in landscape ink.
struct JourneyLink: View {
    /// What it says.
    let title: LocalizedStringKey
    /// The identifier the UI tests find it by.
    var identifier = "onboarding-skip"
    /// What it does.
    let action: () -> Void

    /// The view's content.
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .rounded, weight: .bold))
                .journeyVibrant()
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// A line of small print in landscape ink.
struct JourneyNote: View {
    /// What it says.
    let text: LocalizedStringKey

    /// The view's content.
    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            .journeyVibrant()
            .frame(maxWidth: .infinity)
    }
}

/// What a pill shows at its end: whether it is on, and what tapping it does.
enum JourneyIndicator {
    /// + that turns into −: for adding to a set.
    case plusMinus
    /// A check, or an empty ring: for the one choice.
    case check
}

/// A pill a student taps: dashed in landscape ink when off, cream when on.
struct JourneyPill<Leading: View, Label: View>: View {
    /// Whether it is on.
    let isOn: Bool
    /// What its end shows.
    var indicator = JourneyIndicator.plusMinus
    /// What tapping it does.
    let action: () -> Void
    /// The avatar.
    @ViewBuilder var leading: Leading
    /// The words.
    @ViewBuilder var label: Label

    /// The view's content.
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading
                    .scaleEffect(isOn ? 1 : 0.9)
                Group {
                    if isOn {
                        label.foregroundStyle(JourneyInk.ink)
                    } else {
                        label.journeyVibrant()
                    }
                }
                .multilineTextAlignment(.leading)
                JourneyToggleMark(isOn: isOn, indicator: indicator)
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background {
                if isOn { Capsule().fill(.clear).journeyCream() }
            }
            .journeyDashed(!isOn)
            .contentShape(.capsule)
        }
        .buttonStyle(JourneyPress())
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// The disc at the end of a ``JourneyPill``.
private struct JourneyToggleMark: View {
    /// Whether the pill is on.
    let isOn: Bool
    /// Which kind of mark.
    let indicator: JourneyIndicator

    /// The view's content.
    var body: some View {
        Group {
            switch indicator {
            case .plusMinus:
                ZStack {
                    // Only the disc takes the landscape's shade; the glyph stays
                    // light on it, as the reference's does.
                    JourneyDisc(fill: isOn ? JourneyInk.action : nil)
                    ZStack {
                        Capsule().frame(width: 14, height: 2.8)
                        // The vertical bar folds away: + becomes −.
                        Capsule().frame(width: 2.8, height: 14).scaleEffect(y: isOn ? 0 : 1)
                    }
                    .foregroundStyle(.white.opacity(isOn ? 1 : 0.9))
                }
                .frame(width: 30, height: 30)
                .rotationEffect(.degrees(isOn ? 180 : 0))
            case .check:
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(JourneyInk.action))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(lineWidth: 2.6)
                        .frame(width: 30, height: 30)
                        .journeyVibrant()
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: isOn)
        .accessibilityHidden(true)
    }
}

/// How far through the journey: a white line over a track in landscape ink.
struct JourneyProgress: View {
    /// 0 at the first step, 1 at the last.
    let fraction: Double
    /// The position, spoken, where the line means nothing.
    let label: String

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .journeyVibrant()
                    .opacity(0.35)
                Capsule()
                    .fill(.white.opacity(0.85))
                    // Never shorter than its own roundness, so the start of the
                    // journey still shows a dot rather than nothing.
                    .frame(width: max(3, proxy.size.width * fraction))
            }
        }
        .frame(height: 3)
        // About a third of the screen, centred: half what the room between
        // the back button and the edge would give it. A hint of how far, not
        // a bar to read.
        .containerRelativeFrame(.horizontal) { width, _ in width * 0.3 }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: fraction)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// A round disc: a solid colour, or, given none, landscape ink.
struct JourneyDisc: View {
    /// The colour, or `nil` for landscape ink.
    var fill: Color?

    /// Whether the reader has asked for less transparency.
    @Environment(\.accessibilityReduceTransparency) private var solid

    /// The view's content.
    var body: some View {
        if let fill {
            Circle().fill(fill)
        } else if solid {
            Circle().fill(Color.black.opacity(0.55))
        } else {
            Circle().fill(JourneyInk.vibrantDisc).blendMode(.multiply)
        }
    }
}

/// A cream row that is not a control: something that is yours, shown.
struct JourneyCard<Leading: View>: View {
    /// The first line.
    let title: Text
    /// The second line.
    let detail: Text
    /// The avatar.
    @ViewBuilder var leading: Leading

    /// The view's content.
    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                title
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                detail
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JourneyInk.inkSoft)
            }
            .foregroundStyle(JourneyInk.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 7)
        .padding(.trailing, 20)
        .padding(.vertical, 7)
        .journeyCream()
        .accessibilityElement(children: .combine)
    }
}

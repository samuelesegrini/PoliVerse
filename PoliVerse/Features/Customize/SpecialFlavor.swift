import SwiftUI

/// A Flavor with pages of its own, written here rather than put together in
/// Personalizza.
///
/// A classic Flavor is the student's: every part of it has a control. A
/// special one is a recipe — colour, typefaces, surfaces, and the shape of
/// Oggi, Corsi, Carriera and Cerca — that only lets the student turn the few
/// knobs it names in its own words. A look keeps just the recipe's name and
/// those knobs (``TodayStyle/special``, ``TodayStyle/specialSettings``), never
/// the recipe itself, so a recipe improved in an update reaches every student
/// already using it. A name this version does not know reads as no recipe:
/// the look falls back to its classic fields, quietly.
nonisolated enum SpecialFlavor: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Tickets, a bookshelf and full colour, tilted as much as the student likes.
    case playful
    /// The day as a technical drawing: white lines and monospaced type on blue
    /// squared paper, always dark.
    case blueprint

    /// The recipe's identity, which is its stored name.
    var id: String { rawValue }

    /// What the Flavor is called.
    var title: LocalizedStringKey {
        switch self {
        case .playful: "Giocherelloso"
        case .blueprint: "Blueprint"
        }
    }

    /// The name a new look made from it takes.
    var name: LocalizedStringResource {
        switch self {
        case .playful: "Giocherelloso"
        case .blueprint: "Blueprint"
        }
    }

    /// One line saying what it does to the app.
    var blurb: LocalizedStringKey {
        switch self {
        case .playful: "Biglietti, scaffali e colori pieni."
        case .blueprint: "La giornata come un disegno tecnico."
        }
    }

    /// The colour pairs the student chooses between: the page's colour and
    /// the one that stands out against it.
    var pairs: [ColourPair] {
        switch self {
        case .playful:
            [ColourPair(name: "Blu Politecnico e mandarino", main: "#0F3D6E", second: "#E8751A"),
             ColourPair(name: "Lampone e menta", main: "#A8325F", second: "#2FA88A"),
             ColourPair(name: "Indaco e corallo", main: "#3B4BC8", second: "#E0584F"),
             ColourPair(name: "Grafite e limone", main: "#1F2328", second: "#E8C21A")]
        case .blueprint:
            // The paper, and the ink that marks what matters on it.
            [ColourPair(name: "Blu cianografia", main: "#1B4A8A", second: "#FFD27A"),
             ColourPair(name: "Notte", main: "#10233D", second: "#7FDBFF"),
             ColourPair(name: "Verde tecnico", main: "#1C5446", second: "#FFE08A"),
             ColourPair(name: "Grafite", main: "#2A2F36", second: "#FF9F6B")]
        }
    }

    /// The pair a setting names, the first when it names none.
    func pair(_ settings: SpecialSettings) -> ColourPair {
        pairs.indices.contains(settings.pair) ? pairs[settings.pair] : pairs[0]
    }

    /// Writes the recipe over a look's classic fields. What the student still
    /// owns — the light, the app half, the name, the bar — is left alone.
    ///
    /// - Parameters:
    ///   - look: The look to write over.
    ///   - settings: The knobs the student turned.
    func apply(to look: inout TodayStyle, settings: SpecialSettings) {
        switch self {
        case .playful:
            let pair = pair(settings)
            look.flavor = Flavor(main: pair.main, accent: pair.second)
            look.dateFont = .futura
            look.dateWeight = 0.6
            look.dateColour = .flavor
            look.textDesign = .standard
            look.material = .solid
            look.paper = .dots
            look.background = .plain
            look.grain = 0
            look.showsGreeting = false
            look.accessory = .none
        case .blueprint:
            let pair = pair(settings)
            look.flavor = Flavor(main: pair.main, accent: pair.second)
            look.dateFont = .mono
            look.dateWeight = 0.8
            look.dateColour = .ink
            look.textDesign = .monospaced
            look.material = .solid
            look.paper = .plain
            look.background = .plain
            look.grain = 0
            look.showsGreeting = false
            look.accessory = .none
            // White lines on blue paper read only one way: the app is dark.
            look.appearance = .dark
        }
    }
}

/// The knobs a special Flavor lets the student turn.
nonisolated struct SpecialSettings: Codable, Equatable, Hashable, Sendable {
    /// How far the cards lean.
    var chaos = Chaos.some
    /// Which of the Flavor's colour pairs is in use.
    var pair = 0
    /// How close the squares of Blueprint's paper are.
    var grid = Grid.fine

    /// Every knob at its starting place.
    init() {}

    /// Reads the knobs, keeping the defaults for anything a stored look does not name.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: Whatever the decoder throws.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chaos = (try? container.decodeIfPresent(Chaos.self, forKey: .chaos)) ?? chaos
        pair = max(try container.decodeIfPresent(Int.self, forKey: .pair) ?? pair, 0)
        grid = (try? container.decodeIfPresent(Grid.self, forKey: .grid)) ?? grid
    }

    /// How close the squares of the paper are, in two steps.
    nonisolated enum Grid: Int, Codable, CaseIterable, Identifiable, Sendable {
        /// Squares of a notebook.
        case fine
        /// Squares of a drawing board.
        case wide

        /// The step's identity, which is its raw value.
        var id: Int { rawValue }

        /// What the step is called.
        var title: LocalizedStringKey {
            switch self {
            case .fine: "Fitta"
            case .wide: "Larga"
            }
        }

        /// The side of a square, in points.
        var spacing: CGFloat {
            switch self {
            case .fine: 20
            case .wide: 36
            }
        }
    }

    /// How far the cards lean, in three steps.
    nonisolated enum Chaos: Int, Codable, CaseIterable, Identifiable, Sendable {
        /// Every card straight.
        case tidy
        /// A slight lean, alternating.
        case some
        /// Leaning like stickers slapped on a notebook.
        case wild

        /// The step's identity, which is its raw value.
        var id: Int { rawValue }

        /// What the step is called.
        var title: LocalizedStringKey {
            switch self {
            case .tidy: "Ordinato"
            case .some: "Un po’"
            case .wild: "Scatenato"
            }
        }

        /// The largest lean, in degrees.
        var degrees: Double {
            switch self {
            case .tidy: 0
            case .some: 1.5
            case .wild: 4
            }
        }
    }
}

/// Two colours chosen together.
nonisolated struct ColourPair: Sendable {
    /// What the pair is called, for VoiceOver.
    let name: LocalizedStringResource
    /// The page's colour.
    let main: Flavor.RGB
    /// The colour that stands out against it.
    let second: Flavor.RGB

    /// A pair from two hex strings, which are written here and always valid.
    init(name: LocalizedStringResource, main: String, second: String) {
        self.name = name
        self.main = Flavor.RGB(hex: main)!
        self.second = Flavor.RGB(hex: second)!
    }
}

nonisolated extension TodayStyle {
    /// The look as the app draws it: a special Flavor's recipe written over
    /// the classic fields, or the look unchanged when it has none.
    var resolved: TodayStyle {
        guard let special else { return self }
        var look = self
        special.apply(to: &look, settings: specialSettings)
        return look
    }

    /// Giocherelloso's lean for the card at a position: alternating, and none
    /// at all in any other Flavor or when the student set it tidy.
    ///
    /// - Parameter index: The card's position in its row or list.
    /// - Returns: The angle to rotate it by.
    func lean(_ index: Int) -> Angle {
        // Only Giocherelloso leans: a drawing is ruled straight.
        guard special == .playful else { return .zero }
        let degrees = specialSettings.chaos.degrees
        let pattern: [Double] = [-1, 0.7, -0.4, 1]
        return .degrees(degrees * pattern[index % pattern.count])
    }
}

extension EnvironmentValues {
    /// The look in use, resolved, as the app root publishes it.
    ///
    /// Read this rather than the stored look: it is decoded once at the root
    /// instead of on every screen, and it already carries a special Flavor's
    /// recipe. Personalizza's previews set their own, so what they draw is the
    /// look being edited.
    @Entry var look: TodayStyle = TodayStyle()
}

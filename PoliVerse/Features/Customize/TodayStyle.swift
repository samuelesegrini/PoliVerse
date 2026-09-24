import SwiftUI

/// How the Oggi page looks: the student's choices from Personalizza.
///
/// A look is a ``Flavor`` (one colour that becomes the whole palette), a
/// ``TodayMaterial`` for the cards, a typeface for the date and a design for
/// the rest of the text, a background pattern, and the page itself: the
/// greeting, the date, stickers beside it and an ordered list of
/// ``TodaySection``s.
nonisolated struct TodayStyle: Equatable, Sendable {
    /// The default look: the Politecnico's navy, soft cards, and Oggi's usual sections.
    init() {}

    /// The typeface the date is set in.
    nonisolated enum DateFont: String, Codable, CaseIterable, Identifiable, Sendable {
        /// The system typeface in its widths and designs.
        case expanded, rounded, serif, mono, condensed, italic
        /// The faces iOS ships, set at a fixed size because they carry no weight axis.
        case didot, futura, avenir, rockwell, bodoni, typewriter, chalkboard
        /// The typeface's identity, which is its raw value.
        var id: String { rawValue }

        /// What the typeface is called in Personalizza.
        var title: LocalizedStringKey {
            switch self {
            case .expanded: "Largo"
            case .rounded: "Arrotondato"
            case .serif: "New York"
            case .mono: "Monospaziato"
            case .condensed: "Stretto"
            case .italic: "Corsivo"
            case .didot: "Didot"
            case .futura: "Futura"
            case .avenir: "Avenir Next"
            case .rockwell: "Rockwell"
            case .bodoni: "Bodoni"
            case .typewriter: "Macchina da scrivere"
            case .chalkboard: "Gessetto"
            }
        }

        /// The installed faces of a named typeface, lightest first; empty
        /// for the system's own designs, which take any weight.
        var faces: [String] {
            switch self {
            case .expanded, .rounded, .serif, .mono, .condensed, .italic: []
            case .didot: ["Didot", "Didot-Bold"]
            case .futura: ["Futura-Medium", "Futura-Bold", "Futura-CondensedExtraBold"]
            case .avenir: ["AvenirNext-UltraLight", "AvenirNext-Regular", "AvenirNext-Medium", "AvenirNext-DemiBold",
                           "AvenirNext-Bold", "AvenirNext-Heavy"]
            case .rockwell: ["Rockwell-Regular", "Rockwell-Bold"]
            case .bodoni: ["BodoniSvtyTwoITCTT-Book", "BodoniSvtyTwoITCTT-Bold"]
            case .typewriter: ["AmericanTypewriter-Light", "AmericanTypewriter", "AmericanTypewriter-Semibold",
                               "AmericanTypewriter-Bold"]
            case .chalkboard: ["ChalkboardSE-Light", "ChalkboardSE-Regular", "ChalkboardSE-Bold"]
            }
        }

        /// The face for a weight on the slider, from 0 to 1.
        func faceName(weight: Double) -> String? {
            guard !faces.isEmpty else { return nil }
            return faces[min(Int(weight.clamped(to: 0...1) * Double(faces.count)), faces.count - 1)]
        }

        /// The typeface at a size and weight.
        ///
        /// - Parameters:
        ///   - size: The point size.
        ///   - weight: 0 for the lightest face, 1 for the heaviest.
        /// - Returns: The font.
        @MainActor func font(size: CGFloat, weight: Double) -> Font {
            let system = TodayStyle.systemWeight(weight)
            switch self {
            case .expanded: return .system(size: size, weight: system).width(.expanded)
            case .rounded: return .system(size: size, weight: system, design: .rounded)
            case .serif: return .system(size: size, weight: system, design: .serif)
            case .mono: return .system(size: size, weight: system, design: .monospaced)
            case .condensed: return .system(size: size, weight: system).width(.compressed)
            case .italic: return .system(size: size, weight: system, design: .serif).italic()
            default:
                // Fixed size: the date sets its own size and scales to fit.
                return .custom(faceName(weight: weight) ?? "", fixedSize: size)
            }
        }
    }

    /// The design of the page's other text: the greeting and the sections.
    nonisolated enum TextDesign: String, Codable, CaseIterable, Identifiable, Sendable {
        /// The four system designs.
        case standard, rounded, serif, monospaced
        /// The design's identity, which is its raw value.
        var id: String { rawValue }

        /// What the design is called in Personalizza.
        var title: LocalizedStringKey {
            switch self {
            case .standard: "Sistema"
            case .rounded: "Arrotondato"
            case .serif: "Con grazie"
            case .monospaced: "Monospaziato"
            }
        }

        /// The design as SwiftUI takes it.
        var design: Font.Design {
            switch self {
            case .standard: .default
            case .rounded: .rounded
            case .serif: .serif
            case .monospaced: .monospaced
            }
        }
    }

    /// The date in the text colour, or in the Flavor's accent.
    nonisolated enum DateColour: String, Codable, CaseIterable, Identifiable, Sendable {
        /// The text colour, or the Flavor's accent.
        case ink, flavor
        /// The choice's identity, which is its raw value.
        var id: String { rawValue }

        /// What the choice is called in Personalizza.
        var title: LocalizedStringKey {
            switch self {
            case .ink: "Inchiostro"
            case .flavor: "Colore"
            }
        }
    }

    /// The one colour the whole palette is built from.
    var flavor = Flavor.polimi
    /// What the page's cards are made of.
    var material = TodayMaterial.soft
    /// The design of the page's text other than the date.
    var textDesign = TextDesign.standard
    /// The typeface the date is set in.
    var dateFont: DateFont = .expanded
    /// 0 is the lightest, 1 the heaviest.
    var dateWeight: Double = 1
    /// A multiplier on the date's natural size.
    var dateSize: Double = 1 {
        didSet { dateSize = dateSize.clamped(to: Self.dateSizes) }
    }
    /// Whether the date takes the text colour or the Flavor's accent.
    var dateColour = DateColour.ink
    /// Whether a greeting sits above the date.
    var showsGreeting = true
    /// The decoration drawn on the page.
    var background: TodayBackground = .plain
    /// Which greeting the page opens with.
    var greeting: GreetingStyle = .classic
    /// The student's own line, for ``GreetingStyle/custom``: one line above
    /// the date, so kept short.
    var customGreeting = "" {
        didSet { if customGreeting.count > Self.customGreetingLimit { customGreeting = String(customGreeting.prefix(Self.customGreetingLimit)) } }
    }
    /// How the date is laid out.
    var dateLayout: DateLayout = .stacked
    /// Which edge the date and greeting sit against.
    var dateAlignment: DateAlignment = .leading
    /// What sits beside the date: nothing, stickers, a photo, or text.
    var accessory = TodayAccessory.none
    /// The stickers and where the student put them.
    var stickers: [PlacedSticker] = []
    /// Stickers get a white cut-out edge, like printed ones.
    var stickerOutline = true
    /// The text accessory.
    var accessoryText = "" {
        didSet { if accessoryText.count > Self.accessoryTextLimit { accessoryText = String(accessoryText.prefix(Self.accessoryTextLimit)) } }
    }
    /// The photo accessory, oldest first; the last is on top.
    var photoIDs: [String] = []
    /// The paper the page is printed on, under any decoration.
    var paper = TodayPaper.plain
    /// Film grain over the page, from none to full.
    var grain: Double = 0 {
        didSet { grain = grain.clamped(to: 0...1) }
    }
    /// How the app is lit, and how strongly the Flavor colours it.
    var appearance = TodayAppearance.system
    /// The sections of Oggi, in the order they are drawn.
    var sections: [TodaySection] = TodaySection.defaultKinds.map(TodaySection.init(kind:))
    /// Which of Oggi's optional bar buttons show.
    var bar = TodayBarStyle()
    /// What the rest of the app wears with the page: its tint, icon and tab bar.
    var app = AppLook()
    /// The special Flavor this look is, or `nil` for a classic one. Only the
    /// name is kept: the recipe lives in ``SpecialFlavor`` and is applied by
    /// ``resolved``.
    var special: SpecialFlavor?
    /// The knobs of ``special`` the student turned.
    var specialSettings = SpecialSettings()
    /// What the student calls this look. Empty while it has no name, and the
    /// gallery calls it by its place instead.
    var name = "" {
        didSet { if name.count > Self.nameLimit { name = String(name.prefix(Self.nameLimit)) } }
    }

    /// The range the date's size multiplier is clamped to.
    static let dateSizes = 0.6...1.3
    /// How long the student's own greeting may be.
    static let customGreetingLimit = 40
    /// How long a text accessory may be.
    static let accessoryTextLimit = 24
    /// How long a look's name may be.
    static let nameLimit = 24

    /// The look's name, or its place in the gallery when it has none.
    func displayName(at index: Int) -> String {
        name.isEmpty ? String(localized: "Flavor \(index + 1)") : name
    }

    /// The material a section draws in: its own, or the page's.
    func material(for section: TodaySection) -> TodayMaterial {
        section.material ?? material
    }

    /// The system weight for a slider value.
    static func systemWeight(_ value: Double) -> Font.Weight {
        let steps: [Font.Weight] = [.regular, .medium, .semibold, .bold, .heavy, .black]
        return steps[min(Int((value * Double(steps.count - 1)).rounded()), steps.count - 1)]
    }

    /// The date's weight as SwiftUI takes it.
    var weight: Font.Weight { Self.systemWeight(dateWeight) }

    /// The accent in a colour scheme, readable on the page and on cards.
    @MainActor func accent(_ scheme: ColorScheme) -> Color {
        flavor.accent(dark: scheme == .dark, mode: appearance.flavorMode).color
    }

    /// The Flavor's colours for this look's appearance.
    @MainActor func palette(_ scheme: ColorScheme) -> Flavor.Palette {
        flavor.palette(scheme, mode: appearance.flavorMode)
    }

    /// The date's colour in a colour scheme.
    @MainActor func dateTint(_ scheme: ColorScheme) -> Color {
        dateColour == .flavor ? accent(scheme) : .primary
    }

    /// The accent of buttons, the selected tab and links across the app: the
    /// Flavor's while the app is paired with the page, its own otherwise.
    func controlAccent(dark: Bool) -> Flavor.RGB {
        // Blueprint's main colour is the paper itself, so the usual readable
        // accent is blue on blue. White would read on the paper but vanish
        // under a prominent button's white label; the tone that balances the
        // two is taken instead.
        if special == .blueprint && app.paired { return Self.blueprintControl(paper: flavor) }
        return appFlavor.accent(dark: dark, mode: appearance.flavorMode)
    }

    /// Blueprint's control colour: the paper's hue at the saturation and
    /// brightness that read best both on the paper and the dark pages and
    /// under a white label, since a tint is both a text colour and a fill.
    static func blueprintControl(paper: Flavor) -> Flavor.RGB {
        let hue = paper.main.hsb.0
        let backgrounds = [paper.main, paper.ground(dark: true), paper.surface(dark: true)]
        var best = Flavor.RGB.white, bestScore = 0.0
        for saturation in stride(from: 0.3, through: 0.8, by: 0.1) {
            for brightness in stride(from: 0.5, through: 1.0, by: 0.02) {
                let candidate = Flavor.RGB(hue: hue, saturation: saturation, brightness: brightness)
                let score = (backgrounds + [.white]).map { Flavor.contrast(candidate, $0) }.min() ?? 0
                if score > bestScore { best = candidate; bestScore = score }
            }
        }
        return best
    }

    /// The control accent as a SwiftUI colour.
    ///
    /// - Parameter scheme: Light or dark.
    /// - Returns: The colour.
    @MainActor func controlTint(_ scheme: ColorScheme) -> Color {
        controlAccent(dark: scheme == .dark).color
    }

    /// The `UserDefaults` key the look in use is stored under.
    static let storageKey = "todayStyle"
    /// The `UserDefaults` key the saved looks are stored under.
    static let libraryKey = "todayStyleLibrary"
    /// The `UserDefaults` key the chosen look's index is stored under.
    static let selectionKey = "todayStyleSelection"

    // MARK: - Themes

    /// The themes a student finds before making any looks: the plain
    /// default, then eight, each with its own Flavor, typeface, material and
    /// background, and a different page built on them.
    static var presets: [TodayStyle] {
        // Tramonto: Futura in mandarin on a soft gradient, the lesson now in
        // front, all glass.
        var sunset = TodayStyle()
        sunset.name = "Tramonto"
        sunset.flavor = Flavor(hex: "#E8751A")!
        sunset.dateColour = .flavor
        sunset.dateFont = .futura
        sunset.dateWeight = 0.6
        sunset.textDesign = .rounded
        sunset.material = .glass
        sunset.background = .mesh
        sunset.greeting = .timeOfDay
        sunset.addSection(.currentClass)
        sunset.moveSections([.currentClass], before: .upcoming)
        sunset.updateSection(.currentClass) { $0.tinted = true }

        // Politecnico: Didot in the school's blue, the date in words, frosted
        // cards on a quiet mesh of ovals.
        var polimi = TodayStyle()
        polimi.name = "Politecnico"
        polimi.flavor = Flavor(hex: "#1B4F8F")!
        polimi.dateColour = .flavor
        polimi.dateFont = .didot
        polimi.dateWeight = 0.6
        polimi.dateLayout = .words
        polimi.textDesign = .serif
        polimi.material = .frosted
        polimi.background = .ovals
        polimi.greeting = .motto
        polimi.addSection(.exams)
        polimi.updateSection(.exams) { $0.tinted = true }

        // Minimale: Avenir Next at its lightest, the day's lessons alone,
        // nothing around them.
        var minimal = TodayStyle()
        minimal.name = "Minimale"
        minimal.flavor = Flavor(hex: "#5B6472")!
        minimal.dateFont = .avenir
        minimal.dateWeight = 0.1
        minimal.dateLayout = .bigDay
        minimal.material = .bare
        minimal.background = .dots
        minimal.showsGreeting = false
        minimal.hideSection(.upcoming)
        minimal.updateSection(.timetable) { $0.density = .compact }

        // Studio: bold rounded ink on lavender, tinted glass, books and a
        // pencil beside the date, deadlines first.
        var study = TodayStyle()
        study.name = "Studio"
        study.flavor = Flavor(hex: "#7A6FE0")!
        study.dateFont = .rounded
        study.textDesign = .rounded
        study.material = .tintedGlass
        study.paper = .plot
        study.background = .study
        study.greeting = .name
        study.addSticker(.emoji("📚"), id: presetSticker(1))
        study.addSticker(.emoji("✏️"), id: presetSticker(2))
        study.addSection(.deadlines)
        study.moveSections([.deadlines], before: .upcoming)
        study.hideSection(.upcoming)
        for kind in [TodaySection.Kind.deadlines, .timetable] {
            study.updateSection(kind) { $0.tinted = true }
        }

        // Notte: the weekday tall and centred among the stars, cards that
        // glow in indigo on screens that can.
        var night = TodayStyle()
        night.name = "Notte"
        night.flavor = Flavor(hex: "#3B4BC8")!
        night.dateColour = .flavor
        night.dateFont = .condensed
        night.dateWeight = 0.9
        night.dateLayout = .weekday
        night.dateAlignment = .center
        night.material = .glow
        night.background = .space
        night.greeting = .week
        night.addSection(.currentClass)
        night.moveSections([.currentClass], before: .upcoming)
        night.hideSection(.upcoming)

        // Serra: Bodoni in sage, a leaf beside it, solid compact cards.
        var greenhouse = TodayStyle()
        greenhouse.name = "Serra"
        greenhouse.flavor = Flavor(hex: "#5E8C61")!
        greenhouse.dateColour = .flavor
        greenhouse.dateFont = .bodoni
        greenhouse.dateWeight = 0.7
        greenhouse.textDesign = .serif
        greenhouse.material = .solid
        greenhouse.grain = 0.2
        greenhouse.background = .nature
        greenhouse.greeting = .timeOfDay
        greenhouse.addSticker(.emoji("🌿"), id: presetSticker(3))
        greenhouse.addSection(.exams)
        for kind in [TodaySection.Kind.upcoming, .timetable, .exams] {
            greenhouse.updateSection(kind) { $0.density = .compact; $0.tinted = true }
        }

        // Pausa caffè: typewriter in coffee, the date on one line, a cup and
        // a croissant.
        var coffee = TodayStyle()
        coffee.name = "Pausa caffè"
        coffee.flavor = Flavor(hex: "#8A5A3C")!
        coffee.dateColour = .flavor
        coffee.dateFont = .typewriter
        coffee.dateWeight = 0.7
        coffee.dateLayout = .inline
        coffee.dateSize = 1.3
        coffee.textDesign = .rounded
        coffee.material = .soft
        coffee.paper = .paper
        coffee.grain = 0.35
        coffee.background = .coffee
        coffee.greeting = .motto
        coffee.addSticker(.emoji("☕️"), id: presetSticker(4))
        coffee.addSticker(.emoji("🥐"), id: presetSticker(5))
        coffee.addSection(.currentClass)
        coffee.addSection(.deadlines)
        coffee.moveSections([.currentClass], before: .upcoming)
        coffee.updateSection(.upcoming) { $0.itemLimit = 2 }
        coffee.updateSection(.deadlines) { $0.material = .bare; $0.itemLimit = 2 }

        // Codice: mono in mint on code symbols, clear glass, compact, and
        // only the date and the menu in the bar.
        var code = TodayStyle()
        code.name = "Codice"
        code.flavor = Flavor(hex: "#2FA88A")!
        code.dateColour = .flavor
        code.dateFont = .mono
        code.dateWeight = 0.6
        code.dateAlignment = .trailing
        code.textDesign = .monospaced
        code.material = .clearGlass
        code.background = .coding
        code.greeting = .week
        code.addSection(.exams)
        code.addSection(.deadlines)
        for kind in [TodaySection.Kind.upcoming, .timetable, .exams, .deadlines] {
            code.updateSection(kind) { $0.density = .compact; $0.itemLimit = 2 }
        }
        code.bar.showsProfile = false

        var plain = TodayStyle()
        plain.name = "Base"

        return [plain, sunset, polimi, minimal, study, night, greenhouse, coffee, code]
    }

    /// A fixed id for a preset's sticker, so the presets are the same looks
    /// each time they are built.
    private static func presetSticker(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!
    }

    /// Saved looks, one stored style per line; the presets when there are none.
    static func library(from stored: String, active: TodayStyle) -> [TodayStyle] {
        let looks = stored.split(separator: "\n").compactMap { TodayStyle(rawValue: String($0)) }
        return looks.isEmpty ? presets : looks
    }

    /// The saved looks as one string, one look per line.
    ///
    /// - Parameter looks: The looks to store.
    /// - Returns: The string.
    static func encodeLibrary(_ looks: [TodayStyle]) -> String {
        looks.map(\.rawValue).joined(separator: "\n")
    }

    /// The Flavor for one of the colours looks had before Flavor; nil for
    /// ink, which was no colour.
    static func legacyFlavor(_ accent: String) -> Flavor? {
        switch accent {
        case "polimi": .polimi
        case "orange": Flavor(hex: "#E8751A")
        case "violet": Flavor(hex: "#7A6FE0")
        case "rose": Flavor(hex: "#C2386F")
        case "green": Flavor(hex: "#5E8C61")
        default: nil
        }
    }
}

/// Which optional buttons Oggi's navigation bar shows. Settings and
/// Personalizza are always there: hiding them would leave no way back.
nonisolated struct TodayBarStyle: Codable, Equatable, Hashable, Sendable {
    /// Whether the profile button shows at the bar's leading edge.
    var showsProfile = true
    /// Whether the date shows in the middle of the bar.
    var showsDate = true

    /// Both optional buttons shown.
    init() {}

    /// Reads the choices, keeping the defaults for anything a stored look does not name.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: Whatever the decoder throws.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsProfile = try container.decodeIfPresent(Bool.self, forKey: .showsProfile) ?? showsProfile
        showsDate = try container.decodeIfPresent(Bool.self, forKey: .showsDate) ?? showsDate
    }
}

/// What is stored: the same fields in a plain Codable struct. Kept apart
/// from `TodayStyle` because a `RawRepresentable` string type picks up the
/// standard library's Codable, which encodes `rawValue` instead.
nonisolated private struct StoredTodayStyle: Codable {
    /// The look's Flavor.
    var flavor: Flavor?
    /// What the cards are made of.
    var material: TodayMaterial?
    /// The design of the page's other text.
    var textDesign: TodayStyle.TextDesign?
    /// The date's typeface.
    var dateFont: TodayStyle.DateFont?
    /// The date's weight, 0 to 1.
    var dateWeight: Double?
    /// The multiplier on the date's natural size.
    var dateSize: Double?
    /// Whether the date takes the text colour or the accent.
    var dateColour: TodayStyle.DateColour?
    /// Whether a greeting shows.
    var showsGreeting: Bool?
    /// The page's decoration.
    var background: TodayBackground?
    /// Which greeting the page opens with.
    var greeting: GreetingStyle?
    /// The student's own greeting.
    var customGreeting: String?
    /// How the date is laid out.
    var dateLayout: DateLayout?
    /// Which edge the date sits against.
    var dateAlignment: DateAlignment?
    /// What sits beside the date.
    var accessory: TodayAccessory?
    /// The stickers and where they sit, skipping any that no longer decode.
    var stickers: Lenient<PlacedSticker>?
    /// Whether each sticker gets the look's outline.
    var stickerOutline: Bool?
    /// The words of a text accessory.
    var accessoryText: String?
    /// The ids of the photos in a photo accessory.
    var photoIDs: [String]?
    /// The paper the page is printed on.
    var paper: TodayPaper?
    /// How much grain is rasterised over the page.
    var grain: Double?
    /// How the app is lit.
    var appearance: TodayAppearance?
    /// The sections of Oggi, in order, skipping any that no longer decode.
    var sections: Lenient<TodaySection>?
    /// Which of Oggi's bar controls show.
    var bar: TodayBarStyle?
    /// What the rest of the app wears.
    var app: AppLook?
    /// What the student called the look.
    var name: String?
    /// The special Flavor's name, kept as a string so one this version does
    /// not know reads as none rather than failing the whole look.
    var special: String?
    /// The special Flavor's knobs.
    var specialSettings: SpecialSettings?
}

/// What older versions stored and this one only reads, to carry a look over.
nonisolated private struct LegacyTodayStyle: Decodable {
    /// Before sections: whether In arrivo and the timetable showed.
    var showsUpcoming: Bool?
    /// Before sections: whether the timetable showed.
    var showsTimetable: Bool?
    /// Before Flavor: the date's colour, the background's, the controls'.
    var dateAccent: String?
    /// Before Flavor: the background's colour, as a hex string.
    var backgroundAccent: String?
    /// Before Flavor: the bar's own tint.
    var bar: LegacyBar?
    /// Before accessories: the date alone, or beside stickers.
    var header: String?

    /// The bar as older versions stored it.
    struct LegacyBar: Decodable {
        /// The bar's colour, as a hex string.
        var tint: String?
    }
}

/// Writing a lenient array back out, element by element.
nonisolated extension Lenient: Encodable where Element: Encodable {
    /// Wraps an array for encoding.
    ///
    /// - Parameter elements: The elements.
    init(_ elements: [Element]) {
        self.elements = elements
    }

    /// Writes the elements as a plain array.
    ///
    /// - Parameter encoder: The encoder.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: any Encoder) throws {
        try elements.encode(to: encoder)
    }
}

/// The look as the JSON string `@AppStorage` keeps it in.
nonisolated extension TodayStyle: RawRepresentable {
    /// Reads a look from its stored string, carrying over what older versions wrote.
    ///
    /// - Parameter rawValue: The JSON.
    /// - Returns: `nil` when it is not a stored look.
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredTodayStyle.self, from: data) else { return nil }
        let legacy = try? JSONDecoder().decode(LegacyTodayStyle.self, from: data)
        self.init()
        textDesign = stored.textDesign ?? textDesign
        material = stored.material ?? material
        dateFont = stored.dateFont ?? dateFont
        dateWeight = stored.dateWeight ?? dateWeight
        // Observers do not run in an initialiser: clamp by hand.
        dateSize = (stored.dateSize ?? dateSize).clamped(to: Self.dateSizes)
        showsGreeting = stored.showsGreeting ?? showsGreeting
        background = stored.background ?? background
        greeting = stored.greeting ?? greeting
        customGreeting = String((stored.customGreeting ?? customGreeting).prefix(Self.customGreetingLimit))
        dateLayout = stored.dateLayout ?? dateLayout
        dateAlignment = stored.dateAlignment ?? dateAlignment
        accessory = stored.accessory ?? (legacy?.header == "dateAndStickers" ? .stickers : accessory)
        stickers = stored.stickers?.elements.map { $0.clamped() } ?? stickers
        stickerOutline = stored.stickerOutline ?? stickerOutline
        accessoryText = String((stored.accessoryText ?? accessoryText).prefix(Self.accessoryTextLimit))
        photoIDs = Array((stored.photoIDs ?? photoIDs).suffix(Self.maxPhotos))
        paper = stored.paper ?? paper
        grain = (stored.grain ?? grain).clamped(to: 0...1)
        appearance = stored.appearance ?? appearance
        bar = stored.bar ?? bar
        app = stored.app ?? app
        name = String((stored.name ?? name).prefix(Self.nameLimit))
        special = stored.special.flatMap(SpecialFlavor.init(rawValue:))
        specialSettings = stored.specialSettings ?? specialSettings

        // Before Flavor a look had up to three colours: the date's wins, then
        // the background's, then the controls'; an ink date stays ink.
        let legacyColours = [legacy?.dateAccent, legacy?.backgroundAccent, legacy?.bar?.tint]
            .compactMap { $0 }.compactMap(Self.legacyFlavor)
        flavor = stored.flavor ?? legacyColours.first ?? flavor
        dateColour = stored.dateColour
            ?? (legacy?.dateAccent.flatMap(Self.legacyFlavor) != nil ? .flavor : .ink)

        if let stored = stored.sections {
            // One of each kind, in the stored order.
            var seen = Set<TodaySection.Kind>()
            sections = stored.elements.filter { seen.insert($0.kind).inserted }
        } else {
            // What an older look turned off stays hidden, in its place.
            if legacy?.showsUpcoming == false { hideSection(.upcoming) }
            if legacy?.showsTimetable == false { hideSection(.timetable) }
        }
    }

    /// The look as JSON, with sorted keys so two equal looks give the same string.
    var rawValue: String {
        let stored = StoredTodayStyle(flavor: flavor, material: material, textDesign: textDesign,
                                      dateFont: dateFont, dateWeight: dateWeight, dateSize: dateSize, dateColour: dateColour,
                                      showsGreeting: showsGreeting, background: background,
                                      greeting: greeting, customGreeting: customGreeting,
                                      dateLayout: dateLayout, dateAlignment: dateAlignment, accessory: accessory,
                                      stickers: Lenient(stickers), stickerOutline: stickerOutline, accessoryText: accessoryText,
                                      photoIDs: photoIDs, paper: paper, grain: grain, appearance: appearance,
                                      sections: Lenient(sections), bar: bar, app: app, name: name,
                                      special: special?.rawValue,
                                      specialSettings: special == nil ? nil : specialSettings)
        // Sorted keys: the standard library's `==` for RawRepresentable types
        // compares `rawValue`, and unsorted JSON keys would make equal styles
        // unequal.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? String(data: encoder.encode(stored), encoding: .utf8)) ?? "{}"
    }
}

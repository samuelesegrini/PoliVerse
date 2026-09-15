import SwiftUI

/// How the Oggi page looks: the student's choices from Personalizza.
///
/// A look is a ``Flavor`` (one colour that becomes the whole palette), a
/// ``TodayMaterial`` for the cards, a typeface for the date and a design for
/// the rest of the text, a background pattern, and the page itself: the
/// greeting, the date, stickers beside it and an ordered list of
/// ``TodaySection``s.
nonisolated struct TodayStyle: Equatable, Sendable {
    init() {}

    nonisolated enum DateFont: String, Codable, CaseIterable, Identifiable, Sendable {
        case expanded, rounded, serif, mono, condensed, italic
        case didot, futura, avenir, rockwell, bodoni, typewriter, chalkboard
        var id: String { rawValue }

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
        case standard, rounded, serif, monospaced
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .standard: "Sistema"
            case .rounded: "Arrotondato"
            case .serif: "Con grazie"
            case .monospaced: "Monospaziato"
            }
        }

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
        case ink, flavor
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .ink: "Inchiostro"
            case .flavor: "Flavor"
            }
        }
    }

    var flavor = Flavor.polimi
    var material = TodayMaterial.soft
    var textDesign = TextDesign.standard
    var dateFont: DateFont = .expanded
    /// 0 is the lightest, 1 the heaviest.
    var dateWeight: Double = 1
    /// A multiplier on the date's natural size.
    var dateSize: Double = 1 {
        didSet { dateSize = dateSize.clamped(to: Self.dateSizes) }
    }
    var dateColour = DateColour.ink
    var showsGreeting = true
    var background: TodayBackground = .plain
    var greeting: GreetingStyle = .classic
    /// The student's own line, for ``GreetingStyle/custom``: one line above
    /// the date, so kept short.
    var customGreeting = "" {
        didSet { if customGreeting.count > Self.customGreetingLimit { customGreeting = String(customGreeting.prefix(Self.customGreetingLimit)) } }
    }
    var dateLayout: DateLayout = .stacked
    var dateAlignment: DateAlignment = .leading
    var accessory = TodayAccessory.none
    var stickers: [PlacedSticker] = []
    /// Stickers get a white cut-out edge, like printed ones.
    var stickerOutline = true
    /// The text accessory.
    var accessoryText = "" {
        didSet { if accessoryText.count > Self.accessoryTextLimit { accessoryText = String(accessoryText.prefix(Self.accessoryTextLimit)) } }
    }
    /// The photo accessory, oldest first; the last is on top.
    var photoIDs: [String] = []
    var paper = TodayPaper.plain
    /// Film grain over the page, from none to full.
    var grain: Double = 0 {
        didSet { grain = grain.clamped(to: 0...1) }
    }
    var appearance = TodayAppearance.system
    var sections: [TodaySection] = TodaySection.defaultKinds.map(TodaySection.init(kind:))
    var bar = TodayBarStyle()

    static let dateSizes = 0.6...1.3
    static let customGreetingLimit = 40
    static let accessoryTextLimit = 24

    /// The material a section draws in: its own, or the page's.
    func material(for section: TodaySection) -> TodayMaterial {
        section.material ?? material
    }

    /// The system weight for a slider value.
    static func systemWeight(_ value: Double) -> Font.Weight {
        let steps: [Font.Weight] = [.regular, .medium, .semibold, .bold, .heavy, .black]
        return steps[min(Int((value * Double(steps.count - 1)).rounded()), steps.count - 1)]
    }

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
    /// Flavor's, so the whole app takes the look's colour.
    func controlAccent(dark: Bool) -> Flavor.RGB {
        flavor.accent(dark: dark, mode: appearance.flavorMode)
    }

    @MainActor func controlTint(_ scheme: ColorScheme) -> Color {
        controlAccent(dark: scheme == .dark).color
    }

    static let storageKey = "todayStyle"
    static let libraryKey = "todayStyleLibrary"
    static let selectionKey = "todayStyleSelection"

    // MARK: - Themes

    /// The themes a student finds before making any looks: the plain
    /// default, then eight, each with its own Flavor, typeface, material and
    /// background, and a different page built on them.
    static var presets: [TodayStyle] {
        // Tramonto: Futura in mandarin on a soft gradient, the lesson now in
        // front, all glass.
        var sunset = TodayStyle()
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
        night.bar.showsAdd = false

        // Serra: Bodoni in sage, a leaf beside it, solid compact cards.
        var greenhouse = TodayStyle()
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
        code.bar.showsSettings = false

        return [TodayStyle(), sunset, polimi, minimal, study, night, greenhouse, coffee, code]
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

/// Which buttons Oggi's navigation bar shows. The ••• menu is always there:
/// it is the way back into Personalizza.
nonisolated struct TodayBarStyle: Codable, Equatable, Hashable, Sendable {
    var showsProfile = true
    var showsSettings = true
    var showsAdd = true
    var showsDate = true

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsProfile = try container.decodeIfPresent(Bool.self, forKey: .showsProfile) ?? showsProfile
        showsSettings = try container.decodeIfPresent(Bool.self, forKey: .showsSettings) ?? showsSettings
        showsAdd = try container.decodeIfPresent(Bool.self, forKey: .showsAdd) ?? showsAdd
        showsDate = try container.decodeIfPresent(Bool.self, forKey: .showsDate) ?? showsDate
    }
}

/// What is stored: the same fields in a plain Codable struct. Kept apart
/// from `TodayStyle` because a `RawRepresentable` string type picks up the
/// standard library's Codable, which encodes `rawValue` instead.
nonisolated private struct StoredTodayStyle: Codable {
    var flavor: Flavor?
    var material: TodayMaterial?
    var textDesign: TodayStyle.TextDesign?
    var dateFont: TodayStyle.DateFont?
    var dateWeight: Double?
    var dateSize: Double?
    var dateColour: TodayStyle.DateColour?
    var showsGreeting: Bool?
    var background: TodayBackground?
    var greeting: GreetingStyle?
    var customGreeting: String?
    var dateLayout: DateLayout?
    var dateAlignment: DateAlignment?
    var accessory: TodayAccessory?
    var stickers: Lenient<PlacedSticker>?
    var stickerOutline: Bool?
    var accessoryText: String?
    var photoIDs: [String]?
    var paper: TodayPaper?
    var grain: Double?
    var appearance: TodayAppearance?
    var sections: Lenient<TodaySection>?
    var bar: TodayBarStyle?
}

/// What older versions stored and this one only reads, to carry a look over.
nonisolated private struct LegacyTodayStyle: Decodable {
    /// Before sections: whether In arrivo and the timetable showed.
    var showsUpcoming: Bool?
    var showsTimetable: Bool?
    /// Before Flavor: the date's colour, the background's, the controls'.
    var dateAccent: String?
    var backgroundAccent: String?
    var bar: LegacyBar?
    /// Before accessories: the date alone, or beside stickers.
    var header: String?

    struct LegacyBar: Decodable {
        var tint: String?
    }
}

nonisolated extension Lenient: Encodable where Element: Encodable {
    init(_ elements: [Element]) {
        self.elements = elements
    }

    func encode(to encoder: any Encoder) throws {
        try elements.encode(to: encoder)
    }
}

nonisolated extension TodayStyle: RawRepresentable {
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

    var rawValue: String {
        let stored = StoredTodayStyle(flavor: flavor, material: material, textDesign: textDesign,
                                      dateFont: dateFont, dateWeight: dateWeight, dateSize: dateSize, dateColour: dateColour,
                                      showsGreeting: showsGreeting, background: background,
                                      greeting: greeting, customGreeting: customGreeting,
                                      dateLayout: dateLayout, dateAlignment: dateAlignment, accessory: accessory,
                                      stickers: Lenient(stickers), stickerOutline: stickerOutline, accessoryText: accessoryText,
                                      photoIDs: photoIDs, paper: paper, grain: grain, appearance: appearance,
                                      sections: Lenient(sections), bar: bar)
        // Sorted keys: the standard library's `==` for RawRepresentable types
        // compares `rawValue`, and unsorted JSON keys would make equal styles
        // unequal.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? String(data: encoder.encode(stored), encoding: .utf8)) ?? "{}"
    }
}

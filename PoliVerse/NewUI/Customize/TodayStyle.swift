import SwiftUI

/// How the Oggi page looks: the student's choices from Personalizza.
///
/// Few, curated options with one fine control each, like the Lock Screen
/// clock: a handful of typefaces, a weight slider and a row of colours. Below
/// the date, the page is an ordered list of ``TodaySection``s; beside it, an
/// optional panel of stickers.
nonisolated struct TodayStyle: Equatable, Sendable {
    init() {}

    nonisolated enum DateFont: String, Codable, CaseIterable, Identifiable, Sendable {
        case expanded, rounded, serif, mono, condensed, italic
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .expanded: "Largo"
            case .rounded: "Arrotondato"
            case .serif: "Con grazie"
            case .mono: "Monospaziato"
            case .condensed: "Stretto"
            case .italic: "Corsivo"
            }
        }

        @MainActor func font(size: CGFloat, weight: Font.Weight) -> Font {
            switch self {
            case .expanded: .system(size: size, weight: weight).width(.expanded)
            case .rounded: .system(size: size, weight: weight, design: .rounded)
            case .serif: .system(size: size, weight: weight, design: .serif)
            case .mono: .system(size: size, weight: weight, design: .monospaced)
            case .condensed: .system(size: size, weight: weight).width(.compressed)
            case .italic: .system(size: size, weight: weight, design: .serif).italic()
            }
        }
    }

    nonisolated enum Accent: String, Codable, CaseIterable, Identifiable, Sendable {
        case ink, polimi, orange, violet, rose, green
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .ink: "Inchiostro"
            case .polimi: "Politecnico"
            case .orange: "Arancio"
            case .violet: "Viola"
            case .rose: "Rosa"
            case .green: "Verde"
            }
        }

        @MainActor var color: Color {
            switch self {
            case .ink: .primary
            case .polimi: Theme.brand
            case .orange: Color(red: 0.91, green: 0.46, blue: 0.10)
            case .violet: Color(red: 0.44, green: 0.39, blue: 0.85)
            case .rose: Color(red: 0.85, green: 0.33, blue: 0.48)
            case .green: Color(red: 0.25, green: 0.56, blue: 0.40)
            }
        }

        /// The colour for symbols and patterns, where ink would read as grey.
        @MainActor var highlight: Color { self == .ink ? Theme.brand : color }
    }

    var dateFont: DateFont = .expanded
    /// 0 is regular, 1 is black.
    var dateWeight: Double = 1
    /// A multiplier on the date's natural size.
    var dateSize: Double = 1 {
        didSet { dateSize = dateSize.clamped(to: Self.dateSizes) }
    }
    var dateAccent: Accent = .ink
    var showsGreeting = true
    var background: TodayBackground = .plain
    /// The background's own colour; nil follows the date.
    var backgroundAccent: Accent?
    var greeting: GreetingStyle = .classic
    /// The student's own line, for ``GreetingStyle/custom``: one line above
    /// the date, so kept short.
    var customGreeting = "" {
        didSet { if customGreeting.count > Self.customGreetingLimit { customGreeting = String(customGreeting.prefix(Self.customGreetingLimit)) } }
    }
    var dateLayout: DateLayout = .stacked
    var dateAlignment: DateAlignment = .leading
    var header: HeaderLayout = .date
    var stickers: [PlacedSticker] = []
    var sections: [TodaySection] = TodaySection.defaultKinds.map(TodaySection.init(kind:))
    var bar = TodayBarStyle()

    static let dateSizes = 0.6...1.3
    static let customGreetingLimit = 40

    /// The accent the background is drawn in: its own, or the date's.
    var backgroundAccentInUse: Accent { backgroundAccent ?? dateAccent }

    /// The pattern's colour; plain ink would read as grey.
    @MainActor var backgroundTint: Color { backgroundAccentInUse.highlight }

    /// The accent of buttons, the selected tab and links: nil keeps the app's.
    var controlAccent: Accent? {
        guard bar.tintFollowsDate else { return bar.tint }
        return dateAccent == .ink ? nil : dateAccent
    }

    @MainActor var controlTint: Color? { controlAccent?.color }

    var weight: Font.Weight {
        let steps: [Font.Weight] = [.regular, .medium, .semibold, .bold, .heavy, .black]
        return steps[min(Int((dateWeight * Double(steps.count - 1)).rounded()), steps.count - 1)]
    }

    static let storageKey = "todayStyle"
    static let libraryKey = "todayStyleLibrary"
    static let selectionKey = "todayStyleSelection"

    /// The looks offered before the student makes any: the plain default,
    /// then eight that each show off a background and a different mix of
    /// type, sections, cards, stickers and colour, to start from.
    static var presets: [TodayStyle] {
        // Warm: rounded orange on a grid, the lesson now in front, all glass.
        var warm = TodayStyle()
        warm.dateAccent = .orange
        warm.dateFont = .rounded
        warm.background = .grid
        warm.greeting = .timeOfDay
        warm.addSection(.currentClass)
        warm.moveSections([.currentClass], before: .upcoming)
        for kind in [TodaySection.Kind.currentClass, .upcoming, .timetable] {
            warm.updateSection(kind) { $0.card = .glass }
        }
        warm.updateSection(.currentClass) { $0.tinted = true }
        warm.bar.tintFollowsDate = true

        // Politecnico: a quiet serif in the school's blue, the date in words.
        var polimi = TodayStyle()
        polimi.dateFont = .serif
        polimi.dateWeight = 0.5
        polimi.dateAccent = .polimi
        polimi.background = .ovals
        polimi.dateLayout = .words
        polimi.greeting = .motto
        polimi.addSection(.exams)
        polimi.updateSection(.exams) { $0.tinted = true }

        // Minimal: thin mono on dots, only the day's lessons, no cards.
        var minimal = TodayStyle()
        minimal.dateFont = .mono
        minimal.dateWeight = 0.2
        minimal.showsGreeting = false
        minimal.hideSection(.upcoming)
        minimal.updateSection(.timetable) { $0.card = .plain; $0.density = .compact }
        minimal.background = .dots
        minimal.dateLayout = .bigDay

        // Study: books and pencils, violet, deadlines first, stickers beside.
        var study = TodayStyle()
        study.dateAccent = .violet
        study.dateFont = .rounded
        study.background = .study
        study.greeting = .name
        study.addSticker(.emoji("📚"), id: presetSticker(1))
        study.addSticker(.emoji("✏️"), id: presetSticker(2))
        study.addSection(.deadlines)
        study.moveSections([.deadlines], before: .upcoming)
        study.hideSection(.upcoming)
        for kind in [TodaySection.Kind.deadlines, .timetable] {
            study.updateSection(kind) { $0.card = .glass; $0.tinted = true }
        }
        study.bar.tint = .violet

        // Space: the weekday large and centred among the stars.
        var space = TodayStyle()
        space.dateAccent = .polimi
        space.dateFont = .condensed
        space.dateLayout = .weekday
        space.dateAlignment = .center
        space.background = .space
        space.greeting = .week
        space.addSection(.currentClass)
        space.moveSections([.currentClass], before: .upcoming)
        space.hideSection(.upcoming)
        for kind in [TodaySection.Kind.currentClass, .timetable] {
            space.updateSection(kind) { $0.card = .glass }
        }
        space.bar.showsAdd = false

        // Nature: green italic, a leaf beside it, exams and what is coming.
        var nature = TodayStyle()
        nature.dateAccent = .green
        nature.dateFont = .italic
        nature.dateWeight = 0.6
        nature.background = .nature
        nature.greeting = .timeOfDay
        nature.addSticker(.emoji("🌿"), id: presetSticker(3))
        nature.addSection(.exams)
        for kind in [TodaySection.Kind.upcoming, .timetable, .exams] {
            nature.updateSection(kind) { $0.density = .compact; $0.tinted = true }
        }
        nature.bar.tintFollowsDate = true

        // Coffee break: rose on cups, one line of date, a cheerful sticker pair.
        var coffee = TodayStyle()
        coffee.dateAccent = .rose
        coffee.dateFont = .rounded
        coffee.dateLayout = .inline
        coffee.dateSize = 1.3
        coffee.background = .coffee
        coffee.greeting = .motto
        coffee.addSticker(.emoji("☕️"), id: presetSticker(4))
        coffee.addSticker(.emoji("🥐"), id: presetSticker(5))
        coffee.addSection(.currentClass)
        coffee.addSection(.deadlines)
        coffee.moveSections([.currentClass], before: .upcoming)
        coffee.updateSection(.upcoming) { $0.itemLimit = 2 }
        coffee.updateSection(.deadlines) { $0.card = .plain; $0.itemLimit = 2 }

        // Code: condensed blue on symbols, compact glass, no profile or settings.
        var code = TodayStyle()
        code.dateAccent = .polimi
        code.dateFont = .condensed
        code.background = .coding
        code.greeting = .week
        code.dateAlignment = .trailing
        code.addSection(.exams)
        code.addSection(.deadlines)
        for kind in [TodaySection.Kind.upcoming, .timetable, .exams, .deadlines] {
            code.updateSection(kind) { $0.card = .glass; $0.density = .compact; $0.itemLimit = 2 }
        }
        code.bar.showsProfile = false
        code.bar.showsSettings = false
        code.bar.tint = .polimi

        return [TodayStyle(), warm, polimi, minimal, study, space, nature, coffee, code]
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
}

/// Oggi's navigation bar and the app's control colour, as a look sets them.
/// The ••• menu is always there: it is the way back into Personalizza.
nonisolated struct TodayBarStyle: Codable, Equatable, Hashable, Sendable {
    var showsProfile = true
    var showsSettings = true
    var showsAdd = true
    var showsDate = true
    /// The colour of buttons, the selected tab and links; nil keeps the app's.
    var tint: TodayStyle.Accent?
    /// The controls take the date's colour instead of ``tint``.
    var tintFollowsDate = false

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsProfile = try container.decodeIfPresent(Bool.self, forKey: .showsProfile) ?? showsProfile
        showsSettings = try container.decodeIfPresent(Bool.self, forKey: .showsSettings) ?? showsSettings
        showsAdd = try container.decodeIfPresent(Bool.self, forKey: .showsAdd) ?? showsAdd
        showsDate = try container.decodeIfPresent(Bool.self, forKey: .showsDate) ?? showsDate
        tint = try container.decodeIfPresent(TodayStyle.Accent.self, forKey: .tint)
        tintFollowsDate = try container.decodeIfPresent(Bool.self, forKey: .tintFollowsDate) ?? tintFollowsDate
    }
}

/// What is stored: the same fields in a plain Codable struct. Kept apart
/// from `TodayStyle` because a `RawRepresentable` string type picks up the
/// standard library's Codable, which encodes `rawValue` instead.
nonisolated private struct StoredTodayStyle: Codable {
    var dateFont: TodayStyle.DateFont?
    var dateWeight: Double?
    var dateSize: Double?
    var dateAccent: TodayStyle.Accent?
    var showsGreeting: Bool?
    /// Before sections: whether In arrivo and the timetable showed. Read
    /// only, to build the sections of an older look.
    var showsUpcoming: Bool?
    var showsTimetable: Bool?
    var background: TodayBackground?
    var backgroundAccent: TodayStyle.Accent?
    var greeting: GreetingStyle?
    var customGreeting: String?
    var dateLayout: DateLayout?
    var dateAlignment: DateAlignment?
    var header: HeaderLayout?
    var stickers: Lenient<PlacedSticker>?
    var sections: Lenient<TodaySection>?
    var bar: TodayBarStyle?
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
        self.init()
        dateFont = stored.dateFont ?? dateFont
        dateWeight = stored.dateWeight ?? dateWeight
        // Observers do not run in an initialiser: clamp by hand.
        dateSize = (stored.dateSize ?? dateSize).clamped(to: Self.dateSizes)
        dateAccent = stored.dateAccent ?? dateAccent
        showsGreeting = stored.showsGreeting ?? showsGreeting
        background = stored.background ?? background
        backgroundAccent = stored.backgroundAccent
        greeting = stored.greeting ?? greeting
        customGreeting = String((stored.customGreeting ?? customGreeting).prefix(Self.customGreetingLimit))
        dateLayout = stored.dateLayout ?? dateLayout
        dateAlignment = stored.dateAlignment ?? dateAlignment
        header = stored.header ?? header
        stickers = stored.stickers?.elements.map { $0.clamped() } ?? stickers
        bar = stored.bar ?? bar
        if let stored = stored.sections {
            // One of each kind, in the stored order.
            var seen = Set<TodaySection.Kind>()
            sections = stored.elements.filter { seen.insert($0.kind).inserted }
        } else {
            // What an older look turned off stays hidden, in its place.
            if stored.showsUpcoming == false { hideSection(.upcoming) }
            if stored.showsTimetable == false { hideSection(.timetable) }
        }
    }

    var rawValue: String {
        let stored = StoredTodayStyle(dateFont: dateFont, dateWeight: dateWeight, dateSize: dateSize, dateAccent: dateAccent,
                                      showsGreeting: showsGreeting, background: background, backgroundAccent: backgroundAccent,
                                      greeting: greeting, customGreeting: customGreeting,
                                      dateLayout: dateLayout, dateAlignment: dateAlignment, header: header,
                                      stickers: Lenient(stickers), sections: Lenient(sections), bar: bar)
        // Sorted keys: the standard library's `==` for RawRepresentable types
        // compares `rawValue`, and unsorted JSON keys would make equal styles
        // unequal.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? String(data: encoder.encode(stored), encoding: .utf8)) ?? "{}"
    }
}

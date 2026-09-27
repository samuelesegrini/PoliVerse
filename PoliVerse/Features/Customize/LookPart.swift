import SwiftUI

/// A part of a look, as Personalizza's editor offers them: a card each in the
/// overview, a name each in the capsule at the bottom.
///
/// A part gathers the pages of controls that change the same thing on the
/// page, and resets on its own: Ripristina il saluto leaves the colours as they are.
enum LookPart: String, CaseIterable, Identifiable {
    /// A classic look's parts, in the order the overview shows them.
    case theme, colour, background, date, greeting, cards, app
    /// A special Flavor's knobs, which stand in for every classic part between Tema and App.
    case special

    /// The part's identity, for accessibility identifiers.
    var id: String { rawValue }

    /// The parts a look has, in order: a special Flavor keeps its page's forms
    /// to itself, so it has only its knobs between Tema and App.
    ///
    /// - Parameter look: The look being edited.
    /// - Returns: Its parts.
    static func parts(for look: TodayStyle) -> [LookPart] {
        look.special == nil
            ? [.theme, .colour, .background, .date, .greeting, .cards, .app]
            : [.theme, .special, .app]
    }

    /// What the part is called on its card and in the capsule.
    var title: LocalizedStringKey {
        switch self {
        case .theme: "Tema"
        case .colour: "Colore"
        case .background: "Sfondo"
        case .date: "Data"
        case .greeting: "Saluto"
        case .cards: "Schede"
        case .app: "App"
        case .special: "Flavor"
        }
    }

    /// The button that puts the part back as editing found it.
    var resetTitle: LocalizedStringKey {
        switch self {
        case .theme: "Ripristina il tema"
        case .colour: "Ripristina i colori"
        case .background: "Ripristina lo sfondo"
        case .date: "Ripristina la data"
        case .greeting: "Ripristina saluto e accessorio"
        case .cards: "Ripristina le schede"
        case .app: "Ripristina l’app"
        case .special: "Ripristina il Flavor"
        }
    }

    /// The pages of controls the part gathers, in the order its tabs show
    /// them. Tema has its own picker, and App its own editor.
    var tools: [CustomizePage] {
        switch self {
        case .colour: [.flavor, .appearance]
        case .background: [.paper]
        case .date: [.widget, .bar]
        case .greeting: [.greeting, .accessory]
        case .cards: [.cards, .layout]
        case .special: [.special]
        case .theme, .app: []
        }
    }

    /// The part a page of controls belongs to, if any.
    ///
    /// - Parameter page: The page.
    init?(page: CustomizePage) {
        guard let part = Self.allCases.first(where: { $0.tools.contains(page) }) else { return nil }
        self = part
    }

    /// The part a zone tapped on the page opens, and which of its tools.
    ///
    /// - Parameters:
    ///   - zone: The zone tapped.
    ///   - look: The look being edited: on a special Flavor every zone is its knobs.
    /// - Returns: The part and the page, or `nil` for a section, which opens its own card.
    static func opening(_ zone: TodayLanding.Zone, in look: TodayStyle) -> (part: LookPart, page: CustomizePage)? {
        if look.special != nil { return (.special, .special) }
        switch zone {
        case .bar: return (.date, .bar)
        case .date: return (.date, .widget)
        case .greeting: return (.greeting, .greeting)
        case .stickers: return (.greeting, .accessory)
        case .background: return (.background, .paper)
        case .section: return nil
        }
    }

    /// The look with this part as it was and everything else as it is.
    ///
    /// - Parameters:
    ///   - look: The look being edited.
    ///   - original: The look as editing found it.
    /// - Returns: The look with the part put back.
    func reset(_ look: TodayStyle, to original: TodayStyle) -> TodayStyle {
        var next = look
        switch self {
        case .theme:
            // Everything the page is drawn with; the name and the app stay.
            next = original
            next.name = look.name
            next.app = look.app
        case .colour:
            next.flavor = original.flavor
            next.appearance = original.appearance
            next.textDesign = original.textDesign
        case .background:
            next.background = original.background
            next.paper = original.paper
            next.grain = original.grain
        case .date:
            next.dateFont = original.dateFont
            next.dateWeight = original.dateWeight
            next.dateSize = original.dateSize
            next.dateColour = original.dateColour
            next.dateLayout = original.dateLayout
            next.dateAlignment = original.dateAlignment
            next.bar = original.bar
        case .greeting:
            next.showsGreeting = original.showsGreeting
            next.greeting = original.greeting
            next.customGreeting = original.customGreeting
            next.accessory = original.accessory
            next.stickers = original.stickers
            next.stickerOutline = original.stickerOutline
            next.accessoryText = original.accessoryText
            next.photoIDs = original.photoIDs
        case .cards:
            next.material = original.material
            next.sections = original.sections
        case .app:
            next.app = original.app
        case .special:
            next.special = original.special
            next.specialSettings = original.specialSettings
        }
        return next
    }
}

extension TodayStyle {
    /// This look wearing a theme: everything the page is drawn with comes from
    /// the theme, while the look keeps its app and the name the student gave
    /// it. A name that only came with a theme goes with it.
    ///
    /// - Parameter theme: A theme or a special Flavor's starting look.
    /// - Returns: The look in the theme.
    func wearing(_ theme: TodayStyle) -> TodayStyle {
        var next = theme
        next.app = app
        let themeNames = Set(Self.presets.map(\.name) + SpecialFlavor.allCases.map { String(localized: $0.name) })
        if !name.isEmpty, !themeNames.contains(name) { next.name = name }
        return next
    }

    /// A special Flavor at its starting knobs, named after it.
    ///
    /// - Parameter special: The special Flavor.
    /// - Returns: Its look.
    static func starting(_ special: SpecialFlavor) -> TodayStyle {
        var look = TodayStyle()
        look.special = special
        look.name = String(localized: special.name)
        return look
    }

    /// A theme's page in a random colour, light and typeface.
    static func surprise() -> TodayStyle {
        var look = presets.randomElement() ?? TodayStyle()
        look.name = ""
        look.flavor = Flavor.swatches.randomElement()?.flavor ?? look.flavor
        look.appearance = LookEditor.variants.randomElement() ?? look.appearance
        look.dateFont = DateFont.allCases.randomElement() ?? look.dateFont
        return look
    }
}

/// Personalizza's undo and redo: every change to the draft, with a burst of
/// changes — a slider dragged, a name typed — taken back as one.
struct EditHistory {
    /// Looks to go back to, the latest last.
    private(set) var past: [TodayStyle] = []
    /// Looks undone, to go forward to again, the latest last.
    private(set) var future: [TodayStyle] = []
    /// When the draft last changed, to tell a burst from a new change.
    private var lastChange = Date.distantPast
    /// The next change is an undo or redo arriving, not an edit.
    private var replaying = false

    /// Changes this close together are one step.
    static let burst: TimeInterval = 0.8

    /// Whether there is anything to undo.
    var canUndo: Bool { !past.isEmpty }
    /// Whether there is anything to redo.
    var canRedo: Bool { !future.isEmpty }

    /// Notes a change to the draft.
    ///
    /// - Parameters:
    ///   - old: The draft before the change.
    ///   - now: When it changed.
    mutating func record(_ old: TodayStyle, at now: Date = .now) {
        if replaying {
            replaying = false
            return
        }
        if past.isEmpty || now.timeIntervalSince(lastChange) > Self.burst {
            past.append(old)
        }
        lastChange = now
        future.removeAll()
    }

    /// Steps back.
    ///
    /// - Parameter current: The draft as it is.
    /// - Returns: The look to go back to, if any.
    mutating func undo(from current: TodayStyle) -> TodayStyle? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return replay(previous, from: current)
    }

    /// Steps forward again.
    ///
    /// - Parameter current: The draft as it is.
    /// - Returns: The look to go forward to, if any.
    mutating func redo(from current: TodayStyle) -> TodayStyle? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return replay(next, from: current)
    }

    /// Readies for the change an undo or redo makes, which is not itself an edit.
    private mutating func replay(_ look: TodayStyle, from current: TodayStyle) -> TodayStyle {
        // No change arrives when the look is already this one.
        replaying = look != current
        lastChange = .distantPast
        return look
    }
}

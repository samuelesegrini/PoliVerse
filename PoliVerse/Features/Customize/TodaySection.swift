import SwiftUI

/// One block of the Oggi page under the date, with how it is drawn.
///
/// A look keeps an ordered list of these: the student reorders, adds and
/// removes them in Personalizza, and each one has its own appearance. A kind
/// appears at most once.
nonisolated struct TodaySection: Equatable, Hashable, Sendable, Identifiable {
    /// What a section lists.
    nonisolated enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        /// The lesson happening now, or the next one today.
        case currentClass
        /// Exams and deadlines coming up.
        case upcoming
        /// The shown day's lessons and exams.
        case timetable
        /// WeBeep assignments still to hand in.
        case deadlines
        /// Exam sittings from today on.
        case exams

        /// The kind's identity, which is its raw value.
        var id: String { rawValue }

        /// What the section is called on the page.
        var title: LocalizedStringKey {
            switch self {
            case .currentClass: "Lezione in corso"
            case .upcoming: "In arrivo"
            case .timetable: "Orario"
            case .deadlines: "Scadenze"
            case .exams: "Esami"
            }
        }

        /// The section's SF Symbol.
        var systemImage: String {
            switch self {
            case .currentClass: "person.bubble"
            case .upcoming: "checklist"
            case .timetable: "calendar.day.timeline.left"
            case .deadlines: "pencil.and.list.clipboard"
            case .exams: "graduationcap"
            }
        }

        /// Lessons, which each have a course colour.
        var hasCourseColours: Bool { self == .timetable }

        /// The forms this kind can take. The current class is a single row
        /// whatever happens, and the timetable's own course-coloured cards
        /// leave only the rail as an alternative.
        var forms: [Form] {
            switch self {
            case .currentClass: [.list]
            case .timetable: [.list, .rail]
            case .upcoming, .deadlines, .exams: Form.allCases
            }
        }

        /// Lists entries that can run long, so the number shown can be chosen.
        /// The timetable always shows the whole day.
        var listsItems: Bool {
            switch self {
            case .upcoming, .deadlines, .exams: true
            case .currentClass, .timetable: false
            }
        }
    }

    /// How a section lays its entries out, chosen like a widget's size.
    nonisolated enum Form: String, Codable, CaseIterable, Identifiable, Sendable {
        /// One row per entry, as sections have always looked.
        case list
        /// The first entry large, the rest as thin rows under it.
        case highlight
        /// Two columns of small cards.
        case tiles
        /// A rail of dates down the left, entries beside it.
        case rail

        /// The form's identity, which is its raw value.
        var id: String { rawValue }

        /// What the form is called in Personalizza.
        var title: LocalizedStringKey {
            switch self {
            case .list: "Elenco"
            case .highlight: "In evidenza"
            case .tiles: "Riquadri"
            case .rail: "Binario"
            }
        }

        /// The form's SF Symbol.
        var systemImage: String {
            switch self {
            case .list: "list.bullet"
            case .highlight: "rectangle.grid.1x2"
            case .tiles: "square.grid.2x2"
            case .rail: "calendar.day.timeline.left"
            }
        }
    }

    /// How much room the section's rows take.
    nonisolated enum Density: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Tight rows, or roomy ones.
        case compact, comfortable

        /// The density's identity, which is its raw value.
        var id: String { rawValue }

        /// What the density is called in Personalizza.
        var title: LocalizedStringKey {
            switch self {
            case .compact: "Compatta"
            case .comfortable: "Ariosa"
            }
        }
    }

    /// What the section lists.
    var kind: Kind
    /// The section's own material; nil draws it in the page's.
    var material: TodayMaterial?
    /// How the entries are laid out; a form the kind cannot take is refused.
    var form: Form = .list {
        didSet { if !kind.forms.contains(form) { form = .list } }
    }
    /// How much room its rows take.
    var density: Density = .comfortable
    /// How many entries a listing section shows.
    var itemLimit = 3 {
        didSet { itemLimit = itemLimit.clamped(to: Self.itemLimits) }
    }
    /// Symbols and highlights take the date's colour.
    var tinted = false
    /// Off the page, keeping its place and settings for when it comes back.
    var isHidden = false
    /// Each lesson on its own card in its course's colour.
    var courseColours = true

    /// The section's identity, which is its kind: a kind appears at most once.
    var id: Kind { kind }

    /// A section of one kind, with every other setting at its default.
    ///
    /// - Parameter kind: What the section lists.
    init(kind: Kind) {
        self.kind = kind
    }

    /// The range ``itemLimit`` is clamped to.
    static let itemLimits = 1...6
    /// The sections a new look starts with.
    static let defaultKinds: [Kind] = [.upcoming, .timetable]
}

/// Settings are read one by one, so a section stored by an older version keeps
/// its defaults for anything it did not have.
nonisolated extension TodaySection: Codable {
    /// Each setting as it is stored.
    private enum CodingKeys: String, CodingKey {
        case kind, material, form, density, itemLimit, tinted, isHidden, courseColours
        /// Before materials: glass, filled or plain.
        case card
    }

    /// Reads a section, keeping the defaults for anything a stored look does not name.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: ``DecodingError`` when the kind is missing or unknown.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        if let stored = try container.decodeIfPresent(TodayMaterial.self, forKey: .material) {
            material = stored
        } else {
            // Glass stays glass and plain becomes bare; filled was the page's
            // look, so it follows the page.
            switch try container.decodeIfPresent(String.self, forKey: .card) {
            case "glass": material = .glass
            case "plain": material = .bare
            default: material = nil
            }
        }
        // Observers do not run in an initialiser: check the kind by hand.
        let stored = try container.decodeIfPresent(Form.self, forKey: .form) ?? form
        form = kind.forms.contains(stored) ? stored : .list
        density = try container.decodeIfPresent(Density.self, forKey: .density) ?? density
        // Observers do not run in an initialiser: clamp by hand.
        itemLimit = (try container.decodeIfPresent(Int.self, forKey: .itemLimit) ?? itemLimit).clamped(to: Self.itemLimits)
        tinted = try container.decodeIfPresent(Bool.self, forKey: .tinted) ?? tinted
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? isHidden
        courseColours = try container.decodeIfPresent(Bool.self, forKey: .courseColours) ?? courseColours
    }

    /// Writes every setting.
    ///
    /// - Parameter encoder: The encoder.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(material, forKey: .material)
        try container.encode(form, forKey: .form)
        try container.encode(density, forKey: .density)
        try container.encode(itemLimit, forKey: .itemLimit)
        try container.encode(tinted, forKey: .tinted)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(courseColours, forKey: .courseColours)
    }
}

/// Decodes a list skipping the entries that fail, such as a section kind from
/// a newer version, instead of losing the whole look.
nonisolated struct Lenient<Element: Decodable>: Decodable {
    /// The entries that decoded.
    let elements: [Element]

    /// Reads the list, dropping whatever fails.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: Whatever reading the list itself throws.
    init(from decoder: any Decoder) throws {
        elements = try [Attempt](from: decoder).compactMap(\.element)
    }

    /// Always decodes, so the list moves past an entry that does not.
    private struct Attempt: Decodable {
        /// The entry, or `nil` when it did not decode.
        let element: Element?

        /// Tries to read one entry, and succeeds either way.
        ///
        /// - Parameter decoder: The decoder.
        init(from decoder: any Decoder) throws {
            element = try? Element(from: decoder)
        }
    }
}

/// Reading and rearranging the look's sections.
nonisolated extension TodayStyle {
    /// The look's section of one kind.
    ///
    /// - Parameter kind: Which kind.
    /// - Returns: The section, or `nil` when the look has none.
    func section(_ kind: TodaySection.Kind) -> TodaySection? {
        sections.first { $0.kind == kind }
    }

    /// The tab bar's current class, unless the page already shows it as a
    /// section: the same lesson twice on one screen reads as two lessons.
    var wantsCurrentClassAccessory: Bool {
        // A special Flavor's Oggi leads with the lesson itself.
        special == nil && !visibleSections.contains { $0.kind == .currentClass }
    }

    /// The sections drawn on the page, in order.
    var visibleSections: [TodaySection] {
        sections.filter { !$0.isHidden }
    }

    /// The kinds not on the page: hidden ones first, as they were, then the
    /// ones never added, in their natural order.
    var addableSections: [TodaySection.Kind] {
        sections.filter(\.isHidden).map(\.kind) + TodaySection.Kind.allCases.filter { section($0) == nil }
    }

    /// Shows a hidden section where it was, or adds a new one at the bottom.
    mutating func addSection(_ kind: TodaySection.Kind) {
        if section(kind) != nil {
            updateSection(kind) { $0.isHidden = false }
        } else {
            sections.append(TodaySection(kind: kind))
        }
    }

    /// Takes a section off the page, keeping its place and settings.
    ///
    /// - Parameter kind: Which section.
    mutating func hideSection(_ kind: TodaySection.Kind) {
        updateSection(kind) { $0.isHidden = true }
    }

    /// Puts `kind` where `target` is, as a drop on it does: moving down lands
    /// after the target, moving up before it.
    mutating func moveSection(_ kind: TodaySection.Kind, onto target: TodaySection.Kind) {
        guard kind != target,
              let from = sections.firstIndex(where: { $0.kind == kind }),
              let to = sections.firstIndex(where: { $0.kind == target }) else { return }
        let moved = sections.remove(at: from)
        sections.insert(moved, at: to)
    }

    /// Swaps a section with the visible one above (-1) or below (+1), for
    /// whoever reorders without dragging.
    mutating func moveSection(_ kind: TodaySection.Kind, by offset: Int) {
        let visible = visibleSections
        guard let index = visible.firstIndex(where: { $0.kind == kind }),
              visible.indices.contains(index + offset) else { return }
        moveSection(kind, onto: visible[index + offset].kind)
    }

    /// Applies a reorder as the system reports it: the lifted sections, in
    /// the order they were picked, go before `target`, or to the end when
    /// there is none. A target among the lifted sections changes nothing.
    mutating func moveSections(_ kinds: [TodaySection.Kind], before target: TodaySection.Kind?) {
        let lifted = kinds.compactMap(section)
        guard !lifted.isEmpty, target.map({ !kinds.contains($0) }) ?? true else { return }
        var rest = sections.filter { !kinds.contains($0.kind) }
        let index = target.flatMap { target in rest.firstIndex { $0.kind == target } } ?? rest.endIndex
        rest.insert(contentsOf: lifted, at: index)
        sections = rest
    }

    /// Changes one section in place, doing nothing when the look has none of that kind.
    ///
    /// - Parameters:
    ///   - kind: Which section.
    ///   - change: What to change about it.
    mutating func updateSection(_ kind: TodaySection.Kind, _ change: (inout TodaySection) -> Void) {
        guard let index = sections.firstIndex(where: { $0.kind == kind }) else { return }
        change(&sections[index])
    }
}

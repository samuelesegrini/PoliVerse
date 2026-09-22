import SwiftUI

/// The day at a glance, drawn in the student's ``TodayStyle``. Shared by the
/// Oggi tab, the single page and Personalizza.
///
/// In Personalizza it comes in two modes. Editing, each zone is outlined and a
/// tap opens its controls. Arranging, reached by holding the page, sections
/// wiggle, lift and move with the system's reordering, can be removed, new
/// ones are added at the bottom, and stickers follow a finger, a pinch and a
/// twist.
struct TodayLanding: View {
    /// A part of the page Personalizza can edit on its own.
    enum Zone: Hashable, Identifiable {
        /// The fixed parts: the navigation bar, the greeting, the date, the accessory and the Flavor behind everything.
        case bar, greeting, date, stickers, background
        /// One of the day's sections.
        case section(TodaySection.Kind)

        /// The zone's identity.
        var id: String {
            switch self {
            case .bar: "bar"
            case .greeting: "greeting"
            case .date: "date"
            case .stickers: "stickers"
            case .background: "background"
            case .section(let kind): "section-\(kind.rawValue)"
            }
        }

        /// What the zone is called in Personalizza.
        var title: LocalizedStringKey {
            switch self {
            case .bar: "Barra"
            case .greeting: "Saluto"
            case .date: "Data"
            case .stickers: "Accessorio"
            case .background: "Flavor"
            case .section(let kind): kind.title
            }
        }
    }

    /// The day the page is about.
    let day: Date
    /// The look the page is drawn in: the draft while editing, the stored one otherwise.
    let style: TodayStyle
    /// The look being edited, or `nil` outside Personalizza — which is also what tells the page it is not being edited.
    private let draft: Binding<TodayStyle>?
    /// True in Personalizza's arranging mode, where sections wiggle and move.
    private let arranging: Bool
    /// Opens a zone's controls.
    private let onEdit: (Zone) -> Void
    /// Opens the sticker picker.
    private let onAddSticker: () -> Void

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session

    /// The page as the app shows it.
    init(day: Date, style: TodayStyle) {
        self.day = day
        self.style = style
        draft = nil
        arranging = false
        onEdit = { _ in }
        onAddSticker = {}
    }

    /// The page in Personalizza, changing the look being edited.
    init(day: Date, draft: Binding<TodayStyle>, arranging: Bool, onAddSticker: @escaping () -> Void,
         onEdit: @escaping (Zone) -> Void) {
        self.day = day
        style = draft.wrappedValue
        self.draft = draft
        self.arranging = arranging
        self.onAddSticker = onAddSticker
        self.onEdit = onEdit
    }

    /// True in Personalizza, in either of its modes.
    private var editing: Bool { draft != nil }

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: editing ? 28 : 24) {
            if editing {
                zone(.bar) {
                    ReplicaNavigationBar(student: session.student, day: day, bar: style.bar)
                        .padding(.horizontal, -16)
                        .tint(style.controlTint(scheme))
                }
            }

            header

            sections

            if arranging, !style.addableSections.isEmpty {
                addSectionMenu
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, editing ? 16 : 12)
        .animation(.snappy, value: style)
    }

    // MARK: - Header

    /// The top of the page: the greeting and date, beside the accessory when there is one.
    @ViewBuilder
    private var header: some View {
        // Editing, an empty right half invites an accessory.
        if style.accessory != .none || (editing && !arranging) {
            // Half and half: the date shrinks to its column rather than
            // pushing the stickers out.
            HStack(alignment: .center, spacing: 12) {
                titles(dateScale: 0.72)
                    .frame(maxWidth: .infinity)
                zone(.stickers,
                     swap: style.accessory == .none ? nil : { cycleAccessory() },
                     remove: style.accessory == .none ? nil : { draft?.wrappedValue.accessory = .none }) {
                    ZStack {
                        if style.accessory == .none {
                            Label("Accessorio", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(style.accent(scheme))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            TodayAccessoryView(
                                style: style,
                                editing: editing,
                                arranging: arranging,
                                onChange: { id, change in draft?.wrappedValue.updateSticker(id, change) },
                                onRemove: { id in draft?.wrappedValue.removeSticker(id) },
                                onAdd: onAddSticker)
                        }
                    }
                    .frame(height: 150)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            titles(dateScale: 1)
        }
    }

    /// The greeting and the date, in the look's own typeface and alignment.
    ///
    /// - Parameter dateScale: How much to shrink the date by when it shares the row with an accessory.
    /// - Returns: The column.
    private func titles(dateScale: CGFloat) -> some View {
        VStack(alignment: style.dateAlignment.horizontal, spacing: editing ? 20 : 8) {
            if style.showsGreeting || editing {
                zone(.greeting, remove: style.showsGreeting ? { draft?.wrappedValue.showsGreeting = false } : nil) {
                    Text(style.greeting.text(for: day, firstName: session.student?.firstName, custom: style.customGreeting))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: style.dateAlignment.frame)
                        .opacity(style.showsGreeting ? 1 : 0.35)
                        .contentTransition(.opacity)
                        .fontDesign(style.textDesign.design)
                }
            }
            zone(.date, swap: { cycleDateLayout() }) {
                DateHeader(day: day, style: style, size: 72 * style.dateSize * dateScale)
            }
        }
    }

    // MARK: - Sections

    /// Arranging, the system reorders: a lifted section leaves a placeholder
    /// that follows the finger, and the drop reports where the sections went.
    @ViewBuilder
    private var sections: some View {
        if arranging {
            // Built only while arranging: a container made disabled and
            // enabled later no longer lifts anything.
            VStack(alignment: .leading, spacing: 28) {
                ForEach(style.visibleSections) { section in
                    // One view per item: a condition at the top of an item's
                    // view makes the container fail on lift ("Unexpected
                    // identifier type"), and the section is full of them.
                    VStack(spacing: 0) { sectionZone(section) }
                }
                .reorderable()
            }
            .reorderContainer(for: TodaySection.self) { difference in
                let target: TodaySection.Kind? = switch difference.destination.position {
                case .before(let kind): kind
                case .end: nil
                }
                withAnimation(.snappy) { draft?.wrappedValue.moveSections(difference.sources, before: target) }
            }
        } else {
            ForEach(style.visibleSections) { section in
                sectionZone(section)
            }
        }
    }

    /// One section, wrapped for whichever mode the page is in: plain, editable, or arranging with its remove button and wiggle.
    ///
    /// - Parameter section: The section to draw.
    /// - Returns: The section.
    @ViewBuilder
    private func sectionZone(_ section: TodaySection) -> some View {
        let view = TodaySectionView(section: section, style: style, day: day, collapsed: arranging, opensDetails: draft == nil)
        if arranging {
            view
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
                // Inside the section's frame, beside its title: a lifted section
                // takes touches only within its bounds.
                .overlay(alignment: .topTrailing) {
                    Button("Nascondi \(Text(section.kind.title))", systemImage: "minus") {
                        withAnimation(.snappy) { draft?.wrappedValue.hideSection(section.kind) }
                    }
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.red, in: .circle)
                    .padding(6)
                    .contentShape(.rect)
                    .accessibilityIdentifier("section-remove-\(section.kind.rawValue)")
                }
                .padding(-10)
                .modifier(Wiggle())
                // A container, so the remove button stays its own element.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("section-\(section.kind.rawValue)")
                // Dragging needs sight and a steady hand: the same moves as actions.
                .accessibilityAction(named: "Sposta su") { move(section.kind, by: -1) }
                .accessibilityAction(named: "Sposta giù") { move(section.kind, by: 1) }
        } else {
            zone(.section(section.kind)) { view }
        }
    }

    /// Moves a section up or down the page, for assistive technologies where dragging is not available.
    ///
    /// - Parameters:
    ///   - kind: The section to move.
    ///   - offset: -1 to move it up, 1 to move it down.
    private func move(_ kind: TodaySection.Kind, by offset: Int) {
        withAnimation(.snappy) { draft?.wrappedValue.moveSection(kind, by: offset) }
    }

    /// The menu at the bottom of the arranging page, offering the sections not on it.
    private var addSectionMenu: some View {
        Menu {
            ForEach(style.addableSections) { kind in
                Button(kind.title, systemImage: kind.systemImage) {
                    withAnimation(.snappy) { draft?.wrappedValue.addSection(kind) }
                }
            }
        } label: {
            Label("Aggiungi sezione", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("section-add")
    }

    // MARK: - Zones

    /// Editing, a zone gets a thin outline and a tap opens its controls — the
    /// Lock Screen's way of splitting the page into small pieces. Arranging,
    /// the outline stays but taps go to what is inside.
    /// Swaps the accessory for the next kind, as Kyo's ⇄ does.
    private func cycleAccessory() {
        let kinds: [TodayAccessory] = [.stickers, .text, .photos]
        let next = kinds[((kinds.firstIndex(of: style.accessory) ?? -1) + 1) % kinds.count]
        withAnimation(.snappy) { draft?.wrappedValue.accessory = next }
    }

    /// Swaps the date for its next layout.
    private func cycleDateLayout() {
        let layouts = DateLayout.allCases
        let next = layouts[((layouts.firstIndex(of: style.dateLayout) ?? -1) + 1) % layouts.count]
        withAnimation(.snappy) { draft?.wrappedValue.dateLayout = next }
    }

    /// Wraps a part of the page as an editable zone: outlined, tappable, and badged with what can be done to it.
    ///
    /// - Parameters:
    ///   - zone: Which zone this is.
    ///   - swap: Changes the zone for another kind, when it has alternatives.
    ///   - remove: Takes the zone off the page, when it can be removed.
    ///   - content: The zone's own content.
    /// - Returns: The zone, or bare content outside Personalizza.
    @ViewBuilder
    private func zone<Content: View>(_ zone: Zone, swap: (() -> Void)? = nil, remove: (() -> Void)? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        if !editing {
            content()
        } else if arranging {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background { outline }
                .padding(-10)
        } else {
            Button { onEdit(zone) } label: {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background { outline }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(-10)
            .accessibilityLabel(Text(zone.title))
            .accessibilityHint("Modifica")
            .accessibilityIdentifier("zone-\(zone.id)")
            // Kyo's badges on the zone's corners: swap for another kind at
            // the top, remove at the bottom, on the outer edge of the page so
            // neighbouring zones never share a corner.
            .overlay(alignment: zone == .stickers ? .topTrailing : .topLeading) {
                if let swap {
                    ZoneBadge(symbol: "arrow.left.arrow.right", label: "Cambia", action: swap)
                        .offset(x: zone == .stickers ? 12 : -12, y: -12)
                        .accessibilityIdentifier("zone-\(zone.id)-swap")
                }
            }
            .overlay(alignment: zone == .greeting ? .topTrailing : zone == .stickers ? .bottomTrailing : .bottomLeading) {
                if let remove {
                    // Stickers and photos go; the greeting is only hidden.
                    ZoneBadge(symbol: "minus", label: zone == .greeting ? "Nascondi" : "Rimuovi", action: remove)
                        .offset(x: zone == .stickers || zone == .greeting ? 12 : -12, y: zone == .greeting ? -12 : 12)
                        .accessibilityIdentifier("zone-\(zone.id)-remove")
                }
            }
        }
    }

    /// The dashed border that marks an editable zone.
    private var outline: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
    }
}

/// A small round badge on a zone's corner.
private struct ZoneBadge: View {
    /// The badge's SF Symbol.
    let symbol: String
    /// What the badge does, for assistive technologies.
    let label: LocalizedStringKey
    /// What the tap does.
    let action: () -> Void

    /// The view's content.
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .frame(width: 24, height: 24)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// The Home Screen's jiggle, a little slower so a page of cards stays calm.
private struct Wiggle: ViewModifier {
    /// Whether the reader has asked for reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The environment's `systemPrefersReducedResourceUsage`.
    @Environment(\.systemPrefersReducedResourceUsage) private var reducedResources
    @State private var phase = Double.random(in: 0...1)

    /// Applies the modifier to `content`.
    ///
    /// - Parameter content: The view being modified.
    /// - Returns: The modified view.
    func body(content: Content) -> some View {
        if reduceMotion || reducedResources {
            content
        } else {
            content.phaseAnimator([-0.6, 0.6]) { view, angle in
                view.rotationEffect(.degrees(angle))
            } animation: { _ in
                .easeInOut(duration: 0.16 + phase * 0.04)
            }
        }
    }
}

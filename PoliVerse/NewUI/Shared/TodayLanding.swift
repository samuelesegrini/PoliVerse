import SwiftUI

/// The day at a glance, drawn in the student's ``TodayStyle``. Shared by the
/// Oggi tab, the single page and Personalizza.
///
/// In Personalizza it comes in two modes. Editing, each zone is outlined and a
/// tap opens its controls. Arranging, reached by holding the page, sections
/// wiggle, can be dragged onto one another to reorder and removed, new ones
/// are added at the bottom, and stickers follow a finger, a pinch and a twist.
struct TodayLanding: View {
    enum Zone: Hashable, Identifiable {
        case bar, greeting, date, stickers, background
        case section(TodaySection.Kind)

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

        var title: LocalizedStringKey {
            switch self {
            case .bar: "Barra e colore"
            case .greeting: "Saluto"
            case .date: "Data"
            case .stickers: "Sticker"
            case .background: "Sfondo"
            case .section(let kind): kind.title
            }
        }
    }

    let day: Date
    let style: TodayStyle
    private let draft: Binding<TodayStyle>?
    private let arranging: Bool
    private let onEdit: (Zone) -> Void
    private let onAddSticker: () -> Void

    @Environment(\.locale) private var locale
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

    private var editing: Bool { draft != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: editing ? 28 : 24) {
            if editing {
                zone(.bar) {
                    ReplicaNavigationBar(student: session.student, day: day, bar: style.bar)
                        .padding(.horizontal, -16)
                        .tint(style.controlTint)
                }
            }

            header

            ForEach(style.visibleSections) { section in
                sectionZone(section)
            }

            if arranging, !style.addableSections.isEmpty {
                addSectionMenu
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, editing ? 16 : 12)
        .animation(.snappy, value: style)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if style.header == .dateAndStickers {
            // Half and half: the date shrinks to its column rather than
            // pushing the stickers out.
            HStack(alignment: .center, spacing: 12) {
                titles(dateScale: 0.72)
                    .frame(maxWidth: .infinity)
                zone(.stickers) {
                    StickerPanel(
                        stickers: style.stickers,
                        editing: editing,
                        arranging: arranging,
                        onChange: { id, change in draft?.wrappedValue.updateSticker(id, change) },
                        onRemove: { id in draft?.wrappedValue.removeSticker(id) },
                        onAdd: onAddSticker)
                    .frame(height: 150)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            titles(dateScale: 1)
        }
    }

    private func titles(dateScale: CGFloat) -> some View {
        VStack(alignment: style.dateAlignment.horizontal, spacing: editing ? 20 : 8) {
            if style.showsGreeting || editing {
                zone(.greeting) {
                    Text(style.greeting.text(for: day, firstName: session.student?.firstName, custom: style.customGreeting))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: style.dateAlignment.frame)
                        .opacity(style.showsGreeting ? 1 : 0.35)
                        .contentTransition(.opacity)
                }
            }
            zone(.date) {
                DateHeader(day: day, style: style, size: 72 * style.dateSize * dateScale)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionZone(_ section: TodaySection) -> some View {
        let view = TodaySectionView(section: section, style: style, day: day)
        if arranging {
            view
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
                .overlay(alignment: .topLeading) {
                    Button("Rimuovi \(Text(section.kind.title))", systemImage: "minus") {
                        withAnimation(.snappy) { draft?.wrappedValue.hideSection(section.kind) }
                    }
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(.red, in: .circle)
                    .offset(x: -8, y: -8)
                    .accessibilityIdentifier("section-remove-\(section.kind.rawValue)")
                }
                .padding(-10)
                .modifier(Wiggle())
                .draggable(section.kind.rawValue) {
                    Label(section.kind.title, systemImage: section.kind.systemImage)
                        .padding(12)
                        .glassEffect(.regular, in: .capsule)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let kind = items.first.flatMap(TodaySection.Kind.init(rawValue:)) else { return false }
                    withAnimation(.snappy) { draft?.wrappedValue.moveSection(kind, onto: section.kind) }
                    return true
                }
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

    private func move(_ kind: TodaySection.Kind, by offset: Int) {
        withAnimation(.snappy) { draft?.wrappedValue.moveSection(kind, by: offset) }
    }

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
    @ViewBuilder
    private func zone<Content: View>(_ zone: Zone, @ViewBuilder content: () -> Content) -> some View {
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
        }
    }

    private var outline: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
    }
}

/// The Home Screen's jiggle, a little slower so a page of cards stays calm.
private struct Wiggle: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Double.random(in: 0...1)

    func body(content: Content) -> some View {
        if reduceMotion {
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

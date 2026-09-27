import SwiftUI
import UIKit

extension EnvironmentValues {
    /// How much smaller than the screen the page is drawn, in Personalizza's
    /// preview: handles on the page divide by it to stay a finger's size.
    @Entry var previewScale: CGFloat = 1
}

extension StickerEdit {
    /// What the action is called.
    var title: LocalizedStringKey {
        switch self {
        case .smaller: "Più piccolo"
        case .bigger: "Più grande"
        case .turn: "Ruota"
        case .duplicate: "Duplica"
        case .front: "Porta in primo piano"
        case .remove: "Rimuovi"
        }
    }

    /// Its SF Symbol.
    var systemImage: String {
        switch self {
        case .smaller: "minus.magnifyingglass"
        case .bigger: "plus.magnifyingglass"
        case .turn: "rotate.right"
        case .duplicate: "plus.square.on.square"
        case .front: "square.3.layers.3d.top.filled"
        case .remove: "trash"
        }
    }
}

/// The panel beside the date: the look's stickers where the student put them.
///
/// In Personalizza's page each sticker drags straight away, and a pinch and a
/// twist size and turn it; a tap selects it, ringed, with a handle on its
/// corner that sizes and turns it with one finger, and its actions in a menu.
/// Arranging, each has a button to take it away. The changes go back through
/// `onChange` and `onEdit`.
struct StickerPanel: View {
    /// The stickers to draw, each placed by fractions of the panel.
    let stickers: [PlacedSticker]
    /// In Personalizza, where an empty panel shows where stickers go.
    var editing = false
    /// In Personalizza's arranging mode, where stickers move and can be removed.
    var arranging = false
    /// In Personalizza's page, where stickers move and can be selected.
    var movable = false
    /// The sticker selected on the page, if any.
    var selected: UUID?
    /// Whether each sticker gets the look's outline.
    var outline = true
    /// Records a change to one sticker's place, size or angle.
    var onChange: (UUID, (inout PlacedSticker) -> Void) -> Void = { _, _ in }
    /// Takes one sticker off the panel.
    var onRemove: (UUID) -> Void = { _ in }
    /// Opens the sticker picker.
    var onAdd: () -> Void = {}
    /// Selects a sticker.
    var onSelect: (UUID) -> Void = { _ in }
    /// Does one of a sticker's actions.
    var onEdit: (UUID, StickerEdit) -> Void = { _, _ in }

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            let panel = proxy.size
            ZStack {
                ForEach(stickers) { sticker in
                    StickerItem(sticker: sticker, panel: panel, arranging: arranging, movable: movable || arranging,
                                selected: movable && selected == sticker.id, outline: outline,
                                full: stickers.count >= TodayStyle.maxStickers,
                                onChange: { change in onChange(sticker.id, change) },
                                onRemove: { onRemove(sticker.id) },
                                onSelect: { onSelect(sticker.id) },
                                onEdit: { edit in onEdit(sticker.id, edit) })
                }
                if stickers.isEmpty && editing {
                    Image(systemName: "face.smiling")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                        .position(x: panel.width / 2, y: panel.height / 2)
                }
            }
            .coordinateSpace(.named(StickerItem.space))
            .overlay(alignment: .bottomTrailing) {
                if arranging && stickers.count < TodayStyle.maxStickers {
                    Button("Aggiungi sticker", systemImage: "plus", action: onAdd)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.small)
                        .accessibilityIdentifier("sticker-add")
                }
            }
        }
        .accessibilityElement(children: arranging || movable ? .contain : .ignore)
        .accessibilityLabel(Text("Sticker"))
    }
}

/// One sticker, placed by fractions of the panel.
private struct StickerItem: View {
    /// The sticker to draw.
    let sticker: PlacedSticker
    /// The panel's size, which the sticker's fractions are read against.
    let panel: CGSize
    /// True in arranging mode, where the sticker has a button to remove it.
    let arranging: Bool
    /// True while the sticker can be moved, resized and turned.
    let movable: Bool
    /// True for the sticker selected on the page: ringed, with its handle.
    let selected: Bool
    /// Whether to draw the look's outline around it.
    let outline: Bool
    /// The panel has no room for a copy.
    let full: Bool
    /// Records a change to this sticker.
    let onChange: ((inout PlacedSticker) -> Void) -> Void
    /// Takes this sticker off the panel.
    let onRemove: () -> Void
    /// Selects this sticker.
    let onSelect: () -> Void
    /// Does one of this sticker's actions.
    let onEdit: (StickerEdit) -> Void

    /// The panel's coordinate space, which the handle measures in.
    static let space = "sticker-panel"

    /// How much smaller the page is drawn, which the handle makes up for.
    @Environment(\.previewScale) private var previewScale
    /// The gesture's live value while it is in progress.
    @GestureState private var drag = CGSize.zero
    /// The gesture's live value while it is in progress.
    @GestureState private var pinch = 1.0
    /// The gesture's live value while it is in progress.
    @GestureState private var twist = Angle.zero
    /// The handle's live size and turn, while it is dragged.
    @GestureState private var handle = HandleChange()

    /// What dragging the handle does so far: a size to multiply by and a turn to add.
    private struct HandleChange: Equatable {
        var scale = 1.0
        var turn = 0.0
    }

    /// The view's content.
    var body: some View {
        let side = panel.height * (sticker.size * pinch * handle.scale).clamped(to: PlacedSticker.sizes)
        let angle = Angle.degrees(sticker.rotation + handle.turn) + twist
        StickerContentView(content: sticker.content)
            .frame(width: side, height: side)
            .stickerOutline(outline)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 10 / previewScale, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2 / previewScale)
                        .padding(-6 / previewScale)
                        .allowsHitTesting(false)
                }
            }
            .rotationEffect(angle)
            .contentShape(.rect)
            .overlay(alignment: .topTrailing) {
                if arranging {
                    Button("Rimuovi sticker", systemImage: "xmark", action: onRemove)
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.black.opacity(0.55), in: .circle)
                        .offset(x: 6, y: -6)
                }
            }
            .overlay {
                if selected { handleView(side: side, angle: angle) }
            }
            .position(x: panel.width * sticker.x + drag.width, y: panel.height * sticker.y + drag.height)
            .gesture(movable ? gestures : nil)
            .onTapGesture { if movable && !arranging { onSelect() } }
            .contextMenu {
                // Nothing to show, and so no menu, outside the page's editor.
                if movable && !arranging { menu }
            }
            .animation(.snappy, value: sticker)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Sticker"))
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityIdentifier("page-sticker")
            .accessibilityAction { onSelect() }
            .accessibilityAction(named: "Sposta a sinistra") { nudge(x: -0.08) }
            .accessibilityAction(named: "Sposta a destra") { nudge(x: 0.08) }
            .accessibilityAction(named: "Sposta su") { nudge(y: -0.08) }
            .accessibilityAction(named: "Sposta giù") { nudge(y: 0.08) }
            .accessibilityAction(named: "Più grande") { onEdit(.bigger) }
            .accessibilityAction(named: "Più piccolo") { onEdit(.smaller) }
            .accessibilityAction(named: "Ruota") { onEdit(.turn) }
            .accessibilityAction(named: "Rimuovi") { onEdit(.remove) }
    }

    /// The sticker's actions, as a long press or a secondary click shows them.
    @ViewBuilder
    private var menu: some View {
        Section {
            ForEach([StickerEdit.bigger, .smaller, .turn], id: \.self) { edit in
                Button(edit.title, systemImage: edit.systemImage) { onEdit(edit) }
            }
        }
        Section {
            Button(StickerEdit.duplicate.title, systemImage: StickerEdit.duplicate.systemImage) { onEdit(.duplicate) }
                .disabled(full)
            Button(StickerEdit.front.title, systemImage: StickerEdit.front.systemImage) { onEdit(.front) }
        }
        Button(StickerEdit.remove.title, systemImage: StickerEdit.remove.systemImage, role: .destructive) { onEdit(.remove) }
    }

    /// Moves the sticker by a fraction of the panel, for assistive technologies.
    private func nudge(x: Double = 0, y: Double = 0) {
        onChange {
            $0.x += x
            $0.y += y
        }
    }

    /// The handle on the selected sticker's lower corner: dragged away from
    /// the middle it grows the sticker, dragged round it turns it. Drawn at a
    /// finger's size whatever the page's scale.
    private func handleView(side: CGFloat, angle: Angle) -> some View {
        let knob = 26 / previewScale
        // The lower trailing corner, turned with the sticker.
        let reach = side / 2 + 6 / previewScale
        let radians = angle.radians
        let offset = CGSize(width: reach * cos(radians) - reach * sin(radians),
                            height: reach * sin(radians) + reach * cos(radians))
        let centre = CGPoint(x: panel.width * sticker.x, y: panel.height * sticker.y)
        return Circle()
            .fill(.white)
            .overlay { Circle().strokeBorder(.tint, lineWidth: 2 / previewScale) }
            .shadow(color: .black.opacity(0.25), radius: 3 / previewScale)
            .frame(width: knob, height: knob)
            .contentShape(Circle().inset(by: -8 / previewScale))
            .offset(offset)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .updating($handle) { value, state, _ in
                        state = Self.handleChange(from: value, centre: centre)
                    }
                    .onEnded { value in
                        let change = Self.handleChange(from: value, centre: centre)
                        onChange {
                            $0.size *= change.scale
                            $0.rotation += change.turn
                        }
                    }
            )
            .accessibilityHidden(true)
    }

    /// What a drag of the handle means: the distance from the sticker's
    /// middle, against where it started, is the size; the angle is the turn.
    private static func handleChange(from value: DragGesture.Value, centre: CGPoint) -> HandleChange {
        let start = CGSize(width: value.startLocation.x - centre.x, height: value.startLocation.y - centre.y)
        let now = CGSize(width: value.location.x - centre.x, height: value.location.y - centre.y)
        let from = max(hypot(start.width, start.height), 8)
        let to = hypot(now.width, now.height)
        let turn = (atan2(now.height, now.width) - atan2(start.height, start.width)) * 180 / .pi
        return HandleChange(scale: to / from, turn: turn)
    }

    /// Drag, pinch and twist at once, each writing back when it ends.
    private var gestures: some Gesture {
        // A few points of travel first, so a tap still selects or reaches the
        // remove button, and a swipe that starts elsewhere still scrolls.
        let move = DragGesture(minimumDistance: 4)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                onChange {
                    $0.x += value.translation.width / max(panel.width, 1)
                    $0.y += value.translation.height / max(panel.height, 1)
                }
            }
        let resize = MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in onChange { $0.size *= value.magnification } }
        let turn = RotateGesture()
            .updating($twist) { value, state, _ in state = value.rotation }
            .onEnded { value in onChange { $0.rotation += value.rotation.degrees } }
        return move.simultaneously(with: resize.simultaneously(with: turn))
    }
}

/// A sticker's picture: an emoji as text, a keyboard sticker as its image.
struct StickerContentView: View {
    /// What the sticker is: an emoji, or a stored image.
    let content: PlacedSticker.Content
    /// Fills the frame, cropping, as a photo does; stickers fit whole.
    var fill = false

    /// The view's content.
    var body: some View {
        switch content {
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: 200))
                .minimumScaleFactor(0.05)
                .lineLimit(1)
        case .image(let id):
            if let image = StickerImages.image(for: id) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Decoded sticker images, kept while the app runs: every card of the gallery
/// draws them, and decoding a multi-resolution image each time would stutter.
enum StickerImages {
    /// Decoded images by sticker id, dropped under memory pressure.
    private static let cache = NSCache<NSString, UIImage>()

    /// A sticker's image, decoded once and kept.
    ///
    /// - Parameter id: The sticker's id in ``StickerStore``.
    /// - Returns: The image, or `nil` when there is none to decode.
    static func image(for id: String) -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let data = StickerStore.shared.data(for: id), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: id as NSString)
        return image
    }
}

/// Picks stickers the only way iOS hands them to an app: from the emoji
/// keyboard, whose sticker drawer holds Messages stickers, Live Stickers,
/// Memoji and Genmoji. Emoji typed there become stickers too.
struct StickerPicker: View {
    /// How many more stickers the look has room for.
    let remaining: Int
    /// Adds one picked sticker to the look.
    let onPick: (PlacedSticker.Content) -> Void
    /// Where picked images are saved.
    private let store = StickerStore.shared
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss
    @State private var picked = 0

    /// The view's content.
    var body: some View {
        VStack(spacing: 16) {
            Text("Scegli uno sticker o un’emoji dalla tastiera.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            StickerKeyboard { pick in
                // Past the limit nothing is kept, not even the image file.
                guard picked < remaining else { return }
                let content: PlacedSticker.Content
                switch pick {
                case .emoji(let emoji): content = .emoji(emoji)
                case .image(let data):
                    guard let id = try? store.save(data) else { return }
                    content = .image(id)
                }
                picked += 1
                onPick(content)
                if picked >= remaining { dismiss() }
            }
            .frame(height: 56)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 16))
            if picked > 0 {
                Text("Aggiunti: \(picked)")
                    .font(.footnote.weight(.medium))
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        // In a sheet over Personalizza's editor, which it closes once full.
        .panelTitle("Aggiungi sticker")
    }
}

/// A text view that opens on the emoji keyboard and accepts adaptive image
/// glyphs, turning whatever lands in it into sticker picks, then emptying.
private struct StickerKeyboard: UIViewRepresentable {
    /// What the keyboard put in, before anything is saved.
    enum Pick {
        /// An emoji typed on the keyboard.
        case emoji(String)
        /// A sticker's image, as the keyboard handed it over.
        case image(Data)
    }

    /// Called for each thing the keyboard puts in.
    let onPick: (Pick) -> Void

    /// Builds the text view, set up for adaptive image glyphs.
    ///
    /// - Parameter context: The representable's context.
    /// - Returns: The view.
    func makeUIView(context: Context) -> EmojiTextView {
        let view = EmojiTextView()
        view.supportsAdaptiveImageGlyph = true
        view.font = .systemFont(ofSize: 34)
        view.textAlignment = .center
        view.backgroundColor = .clear
        view.tintColor = .clear
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "sticker-keyboard"
        view.accessibilityLabel = String(localized: "Scegli uno sticker o un’emoji dalla tastiera.")
        return view
    }

    /// Keeps the coordinator's callback current.
    ///
    /// - Parameters:
    ///   - view: The text view.
    ///   - context: The representable's context.
    func updateUIView(_ view: EmojiTextView, context: Context) {
        context.coordinator.onPick = onPick
    }

    /// Creates the delegate that reads picks out of the view.
    ///
    /// - Returns: The coordinator.
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    /// Turns whatever the keyboard puts in the view into picks, then empties it.
    final class Coordinator: NSObject, UITextViewDelegate {
        /// Called for each pick.
        var onPick: (Pick) -> Void

        /// Creates the coordinator.
        ///
        /// - Parameter onPick: Called for each pick.
        init(onPick: @escaping (Pick) -> Void) {
            self.onPick = onPick
        }

        /// Reads every glyph and sticker emoji out of the view, empties it, and reports them.
        ///
        /// - Parameter textView: The view the keyboard wrote into.
        func textViewDidChange(_ textView: UITextView) {
            let text = textView.attributedText ?? NSAttributedString()
            guard text.length > 0 else { return }
            var picks: [Pick] = []
            text.enumerateAttribute(.adaptiveImageGlyph, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                if let glyph = value as? NSAdaptiveImageGlyph {
                    picks.append(.image(glyph.imageContent))
                } else {
                    let plain = (text.string as NSString).substring(with: range)
                    picks += plain.filter(\.isStickerEmoji).map { .emoji(String($0)) }
                }
            }
            textView.attributedText = NSAttributedString()
            picks.forEach(onPick)
        }
    }
}

/// Opens straight on the emoji keyboard, where the stickers are.
final class EmojiTextView: UITextView {
    /// Focused once on screen: the keyboard is the whole point of the view.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    /// The emoji keyboard, where the stickers are, falling back to the system's choice.
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}

/// Which characters count as stickers.
private extension Character {
    /// An emoji a person would pick, not a digit or letter that happens to
    /// have an emoji form.
    var isStickerEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}

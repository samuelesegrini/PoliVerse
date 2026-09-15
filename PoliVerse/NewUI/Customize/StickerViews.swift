import SwiftUI
import UIKit

/// The panel beside the date: the look's stickers where the student put them.
///
/// Arranging, each sticker follows a finger, a pinch and a twist, and has a
/// button to take it away; the changes go back through `onChange`.
struct StickerPanel: View {
    let stickers: [PlacedSticker]
    /// In Personalizza, where an empty panel shows where stickers go.
    var editing = false
    var arranging = false
    var outline = true
    var onChange: (UUID, (inout PlacedSticker) -> Void) -> Void = { _, _ in }
    var onRemove: (UUID) -> Void = { _ in }
    var onAdd: () -> Void = {}

    var body: some View {
        GeometryReader { proxy in
            let panel = proxy.size
            ZStack {
                ForEach(stickers) { sticker in
                    StickerItem(sticker: sticker, panel: panel, arranging: arranging, outline: outline,
                                onChange: { change in onChange(sticker.id, change) },
                                onRemove: { onRemove(sticker.id) })
                }
                if stickers.isEmpty && editing {
                    Image(systemName: "face.smiling")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                        .position(x: panel.width / 2, y: panel.height / 2)
                }
            }
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
        .accessibilityElement(children: arranging ? .contain : .ignore)
        .accessibilityLabel(Text("Sticker"))
    }
}

/// One sticker, placed by fractions of the panel.
private struct StickerItem: View {
    let sticker: PlacedSticker
    let panel: CGSize
    let arranging: Bool
    let outline: Bool
    let onChange: ((inout PlacedSticker) -> Void) -> Void
    let onRemove: () -> Void

    @GestureState private var drag = CGSize.zero
    @GestureState private var pinch = 1.0
    @GestureState private var twist = Angle.zero

    var body: some View {
        let side = panel.height * sticker.size * pinch
        StickerContentView(content: sticker.content)
            .frame(width: side, height: side)
            .stickerOutline(outline)
            .rotationEffect(.degrees(sticker.rotation) + twist)
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
            .position(x: panel.width * sticker.x + drag.width, y: panel.height * sticker.y + drag.height)
            .gesture(arranging ? gestures : nil)
            .animation(.snappy, value: sticker)
    }

    private var gestures: some Gesture {
        // A few points of travel first, so a tap still reaches the remove
        // button and a swipe that starts elsewhere still scrolls.
        let move = DragGesture(minimumDistance: 6)
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
    let content: PlacedSticker.Content
    /// Fills the frame, cropping, as a photo does; stickers fit whole.
    var fill = false

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
    private static let cache = NSCache<NSString, UIImage>()

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
    let remaining: Int
    let onPick: (PlacedSticker.Content) -> Void
    private let store = StickerStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var picked = 0

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Aggiungi sticker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") { dismiss() }
                        .accessibilityIdentifier("sticker-picker-done")
                }
            }
        }
    }
}

/// A text view that opens on the emoji keyboard and accepts adaptive image
/// glyphs, turning whatever lands in it into sticker picks, then emptying.
private struct StickerKeyboard: UIViewRepresentable {
    /// What the keyboard put in, before anything is saved.
    enum Pick {
        case emoji(String)
        case image(Data)
    }

    let onPick: (Pick) -> Void

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

    func updateUIView(_ view: EmojiTextView, context: Context) {
        context.coordinator.onPick = onPick
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onPick: (Pick) -> Void

        init(onPick: @escaping (Pick) -> Void) {
            self.onPick = onPick
        }

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

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}

private extension Character {
    /// An emoji a person would pick, not a digit or letter that happens to
    /// have an emoji form.
    var isStickerEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}

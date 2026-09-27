import SwiftUI

/// A task on the iPhone editor that takes the screen for a moment: the page
/// zooms onto its top, a bar names the task with Annulla and Fine, and what
/// the task needs docks at the bottom.
enum EditorMode: Hashable {
    /// Placing, sizing and turning the stickers, and adding more.
    case stickers
    /// Writing the student's own greeting.
    case greeting
    /// Writing the few words beside the date.
    case besideText

    /// What the bar calls the task.
    var title: LocalizedStringKey {
        switch self {
        case .stickers: "Sticker"
        case .greeting: "Il tuo saluto"
        case .besideText: "Accanto alla data"
        }
    }
}

extension EnvironmentValues {
    /// The page is in the stickers' task, where the selected sticker shows
    /// its actions above it.
    @Entry var stickerMenu = false
}

/// The bar of a task: Annulla puts things back as they were when it began,
/// Fine keeps them.
struct ModeBar: View {
    /// The task.
    let mode: EditorMode
    /// Leaves the task, dropping what it changed.
    let cancel: () -> Void
    /// Leaves the task, keeping what it changed.
    let done: () -> Void

    /// The view's content.
    var body: some View {
        HStack {
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(.primary)
            .accessibilityLabel(Text("Annulla"))
            .accessibilityIdentifier("customize-mode-cancel")
            Spacer()
            Text(mode.title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: done) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel(Text("Fine"))
            .accessibilityIdentifier("customize-mode-done")
        }
        .frame(height: 48)
    }
}

/// Undo and redo side by side in one capsule, as the design pairs them.
struct UndoRedoCapsule: View {
    /// Whether there is anything to undo.
    let canUndo: Bool
    /// Whether there is anything to redo.
    let canRedo: Bool
    /// Goes back one change.
    let undo: () -> Void
    /// Goes forward one change.
    let redo: () -> Void

    /// The view's content.
    var body: some View {
        HStack(spacing: 0) {
            button("Annulla modifica", symbol: "arrow.uturn.backward", id: "customize-editor-undo",
                   shortcut: KeyboardShortcut("z", modifiers: .command), enabled: canUndo, action: undo)
            button("Ripeti modifica", symbol: "arrow.uturn.forward", id: "customize-editor-redo",
                   shortcut: KeyboardShortcut("z", modifiers: [.command, .shift]), enabled: canRedo, action: redo)
        }
        .padding(.horizontal, 2)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// One of the two.
    private func button(_ label: LocalizedStringKey, symbol: String, id: String, shortcut: KeyboardShortcut,
                        enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 42, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .primary : .tertiary)
        .disabled(!enabled)
        .keyboardShortcut(shortcut)
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(id)
    }
}

/// The capsule at the bottom of the iPhone editor: the parts' names in a row
/// that slides under the finger, the open one in the middle. A swipe sideways
/// goes to the next part, a swipe up back to all of them, as Safari's tab
/// bar does.
struct PartCapsule: View {
    /// The parts, in order.
    let parts: [LookPart]
    /// The open part.
    let current: LookPart
    /// Opens a part.
    let pick: (LookPart) -> Void
    /// Goes back to every part.
    let overview: () -> Void

    /// How far the row has been dragged, while it is.
    @GestureState private var drag = CGSize.zero

    /// Each name's width.
    private static let pill: CGFloat = 92

    /// The view's content.
    var body: some View {
        GeometryReader { proxy in
            let index = CGFloat(parts.firstIndex(of: current) ?? 0)
            let across = max(-160, min(160, drag.width))
            HStack(spacing: 0) {
                ForEach(parts) { part in
                    let chosen = part == current
                    Button { pick(part) } label: {
                        Text(part.title)
                            .font(.subheadline.weight(chosen ? .semibold : .regular))
                            .foregroundStyle(chosen ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: Self.pill, height: 38)
                            .background {
                                if chosen { Capsule().fill(.white.opacity(0.14)) }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("customize-switch-\(part.id)")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .offset(x: proxy.size.width / 2 - (index + 0.5) * Self.pill + across)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .animation(.snappy, value: current)
        }
        .frame(height: 48)
        .clipShape(.capsule)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(.capsule)
        .gesture(
            DragGesture(minimumDistance: 6)
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    let across = value.translation.width, up = value.translation.height
                    if up < -40 && abs(up) > abs(across) {
                        overview()
                        return
                    }
                    guard abs(across) > 40, let index = parts.firstIndex(of: current) else { return }
                    let next = min(max(index + (across < 0 ? 1 : -1), 0), parts.count - 1)
                    if next != index { pick(parts[next]) }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Parti del Flavor"))
        .accessibilityAdjustableAction { direction in
            guard let index = parts.firstIndex(of: current) else { return }
            switch direction {
            case .increment: if index + 1 < parts.count { pick(parts[index + 1]) }
            case .decrement: if index > 0 { pick(parts[index - 1]) }
            @unknown default: break
            }
        }
    }
}

/// The field a writing task docks at the bottom, over the keyboard: the words,
/// how much room is left, and a line about where they go.
struct TypingDock: View {
    /// The words being written.
    @Binding var text: String
    /// The prompt in an empty field.
    let prompt: LocalizedStringKey
    /// How long the words may be.
    let limit: Int
    /// A line under the field.
    let note: LocalizedStringKey
    /// Ends the task, keeping the words.
    let submit: () -> Void

    @FocusState private var focused: Bool

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(prompt, text: Binding { text } set: { text = String($0.prefix(limit)) })
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(submit)
                    .accessibilityIdentifier("customize-mode-field")
                Text(verbatim: "\(text.count)/\(limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(Color(white: 0.11), in: .rect(cornerRadius: 14, style: .continuous))
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear { focused = true }
    }
}

/// What the stickers' task docks at the bottom: how many there are, a way to
/// add more, the outline, and the keyboard while adding.
struct StickerDock: View {
    /// The look being edited.
    @Binding var look: TodayStyle
    /// Whether the keyboard is open to add stickers.
    @Binding var adding: Bool

    /// The view's content.
    var body: some View {
        VStack(spacing: 12) {
            if adding {
                HStack {
                    Text("Aggiungi sticker").font(.headline)
                    Spacer()
                    Button("Fine") { withAnimation(.snappy) { adding = false } }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("sticker-keyboard-done")
                }
                StickerPicker(remaining: TodayStyle.maxStickers - look.stickers.count, onPick: { content in
                    withAnimation(.snappy) { _ = look.addSticker(content) }
                }, closesWhenFull: false)
                .frame(height: 150)
            } else {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.snappy) { adding = true }
                    } label: {
                        Label("Aggiungi sticker", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    .disabled(look.stickers.count >= TodayStyle.maxStickers)
                    .accessibilityIdentifier("sticker-controls-add")
                    Text("\(look.stickers.count) di \(TodayStyle.maxStickers)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Toggle("Bordo bianco", isOn: $look.stickerOutline)
                Text("Trascinali sulla pagina; toccane uno per le sue azioni e la maniglia che lo ingrandisce e lo ruota.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

/// Asking before throwing changes away: on a Mac an alert naming the look,
/// elsewhere the sheet of choices the design shows.
struct DiscardQuestion: ViewModifier {
    /// Whether the editor is a Mac's.
    let onMac: Bool
    /// Whether the question is up.
    @Binding var isPresented: Bool
    /// The look's name.
    let name: String
    /// Throws the changes away and leaves.
    let discard: () -> Void

    /// The content, with the question attached.
    func body(content: Content) -> some View {
        if onMac {
            content.alert(name.isEmpty ? Text("Scartare le modifiche?") : Text("Scartare le modifiche a “\(name)”?"),
                          isPresented: $isPresented) {
                Button("Scarta", role: .destructive, action: discard)
                    .accessibilityIdentifier("customize-editor-discard")
                Button("Continua a modificare", role: .cancel) {}
            } message: {
                Text("Il Flavor torna com’era quando hai aperto Personalizza.")
            }
        } else {
            content.confirmationDialog("Scartare le modifiche?", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Scarta le modifiche", role: .destructive, action: discard)
                    .accessibilityIdentifier("customize-editor-discard")
                Button("Continua a modificare", role: .cancel) {}
            } message: {
                Text("Le modifiche a questo Flavor non verranno salvate.")
            }
        }
    }
}

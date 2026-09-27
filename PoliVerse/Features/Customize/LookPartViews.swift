import PhotosUI
import SwiftUI

/// One part of the look in the editor's overview: a small picture of what the
/// part is now, its name, and in a word what it is set to.
struct LookPartCard: View {
    /// The part.
    let part: LookPart
    /// The look being edited.
    let look: TodayStyle

    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The thumbnail's side.
    static let side: CGFloat = 48

    /// The view's content.
    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: Self.side, height: Self.side)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(part.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                value
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
        .contentShape(.rect(cornerRadius: 20, style: .continuous))
    }

    /// The look drawn as it is now.
    private var drawn: TodayStyle { look.resolved }
    /// The light the look's page is drawn in.
    private var lit: ColorScheme { drawn.appearance.colorScheme ?? scheme }

    /// What the part is set to, in a word.
    @ViewBuilder
    private var value: some View {
        switch part {
        case .theme:
            if look.name.isEmpty { Text("Senza nome") } else { Text(verbatim: look.name) }
        case .colour: Text(verbatim: drawn.flavor.name)
        case .background: Text(look.sheet.title)
        case .date: Text(look.dateFont.title)
        case .greeting:
            if look.showsGreeting { Text(look.greeting.title) } else { Text("Nascosto") }
        case .cards: Text(look.material.title)
        case .app: look.app.paired ? Text("Automatica") : Text("Su misura")
        case .special:
            if let special = look.special { Text(special.title) }
        }
    }

    /// A small picture of the part.
    @ViewBuilder
    private var thumbnail: some View {
        switch part {
        case .theme, .special:
            // The whole page, small.
            LookScreen(look: look, scale: Self.side / LookScreen.reference.height, cornerRadius: 60)
                .frame(width: Self.side, height: Self.side)
                .background(.white.opacity(0.1))
        case .colour:
            // The Flavor's three colours, overlapping.
            ZStack {
                ForEach(Array([drawn.flavor.extraColour, drawn.flavor.accentColour, drawn.flavor.base].enumerated()), id: \.offset) { index, colour in
                    Circle()
                        .fill(colour.color)
                        .frame(width: 22, height: 22)
                        .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
                        .offset(x: CGFloat(index - 1) * -9, y: CGFloat(index - 1) * (index == 1 ? 6 : -3))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.1))
        case .background:
            PaperTile(sheet: look.sheet, style: look, showsTitle: false)
                .environment(\.colorScheme, lit)
        case .date:
            Text(shell.day, format: .dateTime.day())
                .font(drawn.dateFont.font(size: 26, weight: drawn.dateWeight))
                .foregroundStyle(drawn.dateColour == .flavor ? AnyShapeStyle(drawn.accent(lit)) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { LookBackground(style: drawn) }
                .environment(\.colorScheme, lit)
        case .greeting:
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: look.showsGreeting ? "text.bubble.fill" : "bubble")
                    .font(.title3)
                    .foregroundStyle(drawn.accent(lit))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if look.accessory == .stickers, let sticker = look.stickers.first {
                    StickerContentView(content: sticker.content)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(12))
                        .padding(4)
                }
            }
            .background { LookBackground(style: drawn) }
            .environment(\.colorScheme, lit)
        case .cards:
            MaterialPreview(material: drawn.material, style: drawn)
                .environment(\.colorScheme, lit)
        case .app:
            Image(drawn.appIconPreview)
                .resizable()
                .scaledToFill()
        }
    }
}

/// Tema: the whole page in one go, from a classic theme, a special Flavor or
/// the colours of a photo. The look keeps its app, and the name the student gave it.
struct ThemePicker: View {
    /// The look being edited.
    @Binding var look: TodayStyle

    /// Which themes are on the shelf.
    enum Shelf: Hashable {
        case classics, specials
    }

    @State private var shelf: Shelf
    @State private var photoItem: PhotosPickerItem?

    /// A theme's width on the shelf.
    private static let width: CGFloat = 76

    /// A picker over the look's themes, open on the kind the look is now.
    ///
    /// - Parameter look: The look being edited.
    init(look: Binding<TodayStyle>) {
        _look = look
        _shelf = State(initialValue: look.wrappedValue.special == nil ? .classics : .specials)
    }

    /// The view's content.
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                GlassSegmentedPicker("Temi", selection: $shelf, options: [.classics, .specials]) { shelf in
                    switch shelf {
                    case .classics: Text("Classici")
                    case .specials: Text("Speciali")
                    }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Da una foto", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.iconOnly)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Da una foto")
                .accessibilityIdentifier("theme-photo")
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 8) {
                    switch shelf {
                    case .classics:
                        surprise
                            // Casuale stands apart from the themes.
                            .padding(.trailing, 8)
                        ForEach(Array(TodayStyle.presets.enumerated()), id: \.offset) { index, theme in
                            tile(theme, caption: Text(theme.displayName(at: index)), id: "theme-preset-\(index)")
                        }
                    case .specials:
                        ForEach(SpecialFlavor.allCases) { special in
                            tile(.starting(special), caption: Text(special.title), id: "theme-special-\(special.rawValue)")
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let flavor = Flavor.extract(from: image.samplePixels()) {
                    withAnimation(.snappy) {
                        look.flavor = flavor
                        // A special Flavor keeps its own page: only the colour comes from the photo.
                        if look.special == nil {
                            look.appearance = .tinted
                            look.background = .mesh
                        }
                    }
                }
                photoItem = nil
            }
        }
    }

    /// Casuale: a theme's page in a random colour, light and typeface.
    private var surprise: some View {
        Button {
            withAnimation(.snappy) { look = look.wearing(.surprise()) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "shuffle")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: Self.width, height: Self.width * LookScreen.reference.height / LookScreen.reference.width)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
                Text("Casuale")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("theme-surprise")
    }

    /// One theme: the page exactly as it will be, ringed when the look wears it.
    private func tile(_ theme: TodayStyle, caption: Text, id: String) -> some View {
        let chosen = look.wearing(theme) == look
        return Button {
            withAnimation(.snappy) { look = look.wearing(theme) }
        } label: {
            VStack(spacing: 6) {
                LookScreen(look: theme, scale: Self.width / LookScreen.reference.width, cornerRadius: 60)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2.5)
                            .padding(-4)
                    }
                caption
                    .font(.caption.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: Self.width)
            }
            .padding(.top, 4)
            // The page inside takes no touches of its own: the tile is the target.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

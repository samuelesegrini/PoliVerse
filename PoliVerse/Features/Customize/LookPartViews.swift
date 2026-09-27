import PhotosUI
import SwiftUI

/// One part of the look in the editor's overview: a small picture of what the
/// part is now, its name, and in a word what it is set to.
struct LookPartCard: View {
    /// The part.
    let part: LookPart
    /// The look being edited.
    let look: TodayStyle

    /// The view's content.
    var body: some View {
        HStack(spacing: 10) {
            LookPartThumbnail(part: part, look: look)
            VStack(alignment: .leading, spacing: 2) {
                Text(part.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                LookPartValue(part: part, look: look)
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
}

/// What a part is set to, in a word.
struct LookPartValue: View {
    /// The part.
    let part: LookPart
    /// The look being edited.
    let look: TodayStyle

    /// The view's content.
    var body: some View {
        switch part {
        case .theme:
            if look.name.isEmpty { Text("Senza nome") } else { Text(verbatim: look.name) }
        case .colour: Text(verbatim: look.resolved.flavor.name)
        case .background: Text("\(Text(look.paper.title)) · \(Text(look.background.title))")
        case .date: Text(look.dateFont.title)
        case .greeting:
            if look.showsGreeting { Text(look.greeting.title) } else { Text("Nascosto") }
        case .cards: Text(look.material.title)
        case .app: look.app.paired ? Text("Automatica") : Text("Su misura")
        case .special:
            if let special = look.special { Text(special.title) }
        }
    }
}

/// A small picture of one part of the look as it is now: the page, the
/// Flavor's colours, the paper, the date's typeface, the greeting, the cards'
/// surface or the app's icon.
struct LookPartThumbnail: View {
    /// The part.
    let part: LookPart
    /// The look being edited.
    let look: TodayStyle
    /// The picture's side.
    var side: CGFloat = 48

    /// The environment's `shell`.
    @Environment(\.shell) private var shell
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        thumbnail
            .frame(width: side, height: side)
            .clipShape(.rect(cornerRadius: side / 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: side / 4, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }

    /// The look drawn as it is now.
    private var drawn: TodayStyle { look.resolved }
    /// The light the look's page is drawn in.
    private var lit: ColorScheme { drawn.appearance.colorScheme ?? scheme }
    /// How much larger than the overview's the picture is.
    private var zoom: CGFloat { side / 48 }

    /// The picture itself.
    @ViewBuilder
    private var thumbnail: some View {
        switch part {
        case .theme, .special:
            // The whole page, small.
            LookScreen(look: look, scale: side / LookScreen.reference.height, cornerRadius: 60)
                .frame(width: side, height: side)
                .background(.white.opacity(0.1))
        case .colour:
            // Main and Accent, as cones side by side.
            HStack(spacing: -8 * zoom) {
                ConeSwatch(colour: drawn.flavor.base, side: 24 * zoom)
                ConeSwatch(colour: drawn.flavor.accentColour, side: 24 * zoom)
                    .overlay { Circle().strokeBorder(Color(white: 0.17), lineWidth: 1.5) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.17))
        case .background:
            // The page's paper with its pattern, and its corner folded.
            TodayBackgroundView(style: drawn)
                .overlay(alignment: .bottomTrailing) {
                    Triangle()
                        .fill(drawn.flavor.ground(dark: lit == .dark, mode: drawn.appearance.flavorMode).mixed(with: .black, 0.18).color)
                        .frame(width: 14 * zoom, height: 14 * zoom)
                }
                .environment(\.colorScheme, lit)
        case .date:
            Text(shell.day, format: .dateTime.day())
                .font(drawn.dateFont.font(size: 26 * zoom, weight: drawn.dateWeight))
                .foregroundStyle(drawn.dateColour == .flavor ? AnyShapeStyle(drawn.accent(lit)) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { LookBackground(style: drawn) }
                .environment(\.colorScheme, lit)
        case .greeting:
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: look.showsGreeting ? "text.bubble.fill" : "bubble")
                    .font(.system(size: 20 * zoom))
                    .foregroundStyle(drawn.accent(lit))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if look.accessory == .stickers, let sticker = look.stickers.first {
                    StickerContentView(content: sticker.content)
                        .frame(width: 20 * zoom, height: 20 * zoom)
                        .rotationEffect(.degrees(12))
                        .padding(4 * zoom)
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

/// One theme on Tema's shelf: the top of the page it makes, ringed when the
/// look wears it. A long press, or a secondary click, offers to take only
/// part of it: its colours, its background or its date.
struct ThemeTile: View {
    /// The look being edited.
    @Binding var look: TodayStyle
    /// The theme.
    let theme: TodayStyle
    /// What it is called.
    let caption: Text
    /// Marks a special Flavor, which changes the whole app.
    var special = false

    /// The tile's size, the top of a page.
    static let size = CGSize(width: 72, height: 108)

    /// The view's content.
    var body: some View {
        let chosen = look.wearing(theme) == look
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button {
            withAnimation(.snappy) { look = look.wearing(theme) }
        } label: {
            VStack(spacing: 7) {
                LookScreen(look: theme, scale: Self.size.width / LookScreen.reference.width, cornerRadius: 0)
                    .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
                    .clipShape(shape)
                    .overlay(alignment: .topTrailing) {
                        if special {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(.black.opacity(0.55), in: .circle)
                                .padding(6)
                        }
                    }
                    .chosenRing(chosen, in: shape)
                caption
                    .font(.caption.weight(chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: Self.size.width + 4)
            }
            // The page inside takes no touches of its own: the tile is the target.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Usa “\(caption)”", systemImage: "checkmark.circle") { take(.all) }
            if theme.special == nil {
                Button("Solo i colori", systemImage: "paintpalette") { take(.colours) }
                Button("Solo lo sfondo", systemImage: "square.dashed") { take(.background) }
                Button("Solo la data", systemImage: "textformat.size") { take(.date) }
            }
        } preview: {
            LookScreen(look: theme, scale: 0.5, cornerRadius: 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    /// Takes the theme, or one part of it.
    private func take(_ slice: ThemeSlice) {
        withAnimation(.snappy) { look = look.wearing(theme, only: slice) }
    }
}

/// Casuale: a theme's page in a random colour, light and typeface, set apart
/// at the start of the classics.
struct SurpriseTile: View {
    /// The look being edited.
    @Binding var look: TodayStyle

    /// The view's content.
    var body: some View {
        Button {
            withAnimation(.snappy) { look = look.wearing(.surprise()) }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: "shuffle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: ThemeTile.size.width, height: ThemeTile.size.height)
                    .background(Color(white: 0.11), in: .rect(cornerRadius: 16, style: .continuous))
                    .chosenRing(false, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Casuale")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Casuale"))
        .accessibilityIdentifier("theme-surprise")
    }
}

/// The folded corner of a page: the lower right half of a square.
private struct Triangle: Shape {
    /// The fold's outline.
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

import SwiftUI

// Blueprint's pieces, shared by its pages: squared blue paper, white lines,
// boxes with a lettered label in their top edge, dimension lines between two
// times, and monospaced type throughout. The app is dark in Blueprint, so
// `.primary` is already the white of the lines.

/// Blueprint's colours: the paper, and the ink that marks what matters on it.
struct BlueprintPalette {
    /// The paper.
    let paper: Color
    /// The lines and the type.
    let ink = Color.white
    /// Secondary lines and captions.
    let faint = Color.white.opacity(0.72)
    /// What matters most: the one deadline that closes soon, the now line.
    let mark: Color

    /// The palette of a look.
    ///
    /// - Parameter style: The look, already resolved.
    init(_ style: TodayStyle) {
        paper = style.flavor.main.color
        mark = style.flavor.colour(.accent).color
    }
}

extension Font {
    /// Blueprint's type: the system's monospaced face, scaling with the reader's text size.
    ///
    /// - Parameters:
    ///   - size: The size at the default text size.
    ///   - bold: Bold rather than medium.
    ///   - relativeTo: The text style it scales with.
    /// - Returns: The font.
    static func blueprint(_ size: CGFloat, bold: Bool = false, relativeTo style: UIFont.TextStyle = .body) -> Font {
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .medium)
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: base))
    }
}

/// The page itself: blue paper squared in white, a heavier line every fifth square.
struct BlueprintPaper: View {
    /// The look, already resolved.
    let style: TodayStyle

    /// The view's content.
    var body: some View {
        let spacing = style.specialSettings.grid.spacing
        Canvas { context, size in
            var fine = Path(), heavy = Path()
            var index = 0
            var x: CGFloat = 0
            while x <= size.width {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                if index % 5 == 0 { heavy.addPath(line) } else { fine.addPath(line) }
                x += spacing; index += 1
            }
            index = 0
            var y: CGFloat = 0
            while y <= size.height {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                if index % 5 == 0 { heavy.addPath(line) } else { fine.addPath(line) }
                y += spacing; index += 1
            }
            context.stroke(fine, with: .color(.white.opacity(0.09)), lineWidth: 1)
            context.stroke(heavy, with: .color(.white.opacity(0.18)), lineWidth: 1)
        }
        .background(style.flavor.main.color)
        .accessibilityHidden(true)
    }
}

/// A page's background in the look: Blueprint's paper, or the page's own
/// paper and decoration for every other Flavor.
struct LookBackground: View {
    /// The look, already resolved.
    let style: TodayStyle
    /// Rounded here for thumbnails, as ``TodayBackgroundView`` rounds itself.
    var cornerRadius: CGFloat = 0

    /// The view's content.
    var body: some View {
        switch style.special {
        case .blueprint:
            BlueprintPaper(style: style)
                .clipShape(.rect(cornerRadius: cornerRadius))
        case .playful, nil:
            TodayBackgroundView(style: style, cornerRadius: cornerRadius)
        }
    }
}

/// A box ruled in white, with its label cut into the top edge.
struct BlueprintBox<Content: View>: View {
    /// The label: a letter and what the box is, "A · PROSSIMA".
    var label: String?
    /// Dashed rather than solid: for what is past or less certain.
    var dashed = false
    /// What is in the box.
    @ViewBuilder let content: Content

    /// The look in use.
    @Environment(\.look) private var style

    /// The view's content.
    var body: some View {
        content
            .padding(14)
            .padding(.top, label == nil ? 0 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: dashed ? [6, 4] : []))
                    .foregroundStyle(.white.opacity(dashed ? 0.7 : 0.95))
            }
            .overlay(alignment: .topLeading) {
                if let label {
                    Text(label)
                        .font(.blueprint(11, relativeTo: .caption2))
                        .tracking(1.5)
                        .padding(.horizontal, 6)
                        .background(style.flavor.main.color)
                        .offset(x: 10, y: -8)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

/// A dimension line: two values with a line between them and a tick at each end.
struct BlueprintDimension: View {
    /// The value at the start.
    let start: String
    /// The value at the end.
    let end: String

    /// The view's content.
    var body: some View {
        HStack(spacing: 6) {
            Text(start)
            HStack(spacing: 0) {
                Rectangle().frame(width: 1, height: 9)
                Rectangle().frame(height: 1)
                Rectangle().frame(width: 1, height: 9)
            }
            .opacity(0.72)
            .accessibilityHidden(true)
            Text(end)
        }
        .font(.blueprint(12, relativeTo: .caption1))
        .accessibilityElement(children: .combine)
    }
}

/// A heading in Blueprint: a letter, a dot and what follows, in small capitals.
struct BlueprintHeading: View {
    /// The words, already in capitals.
    let title: String

    /// The view's content.
    var body: some View {
        Text(title)
            .font(.blueprint(12, bold: true, relativeTo: .subheadline))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row of a Blueprint table, a dashed rule under it.
struct BlueprintRule: View {
    /// The view's content.
    var body: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .foregroundStyle(.white.opacity(0.55))
            .accessibilityHidden(true)
    }
}

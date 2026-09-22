import SwiftUI

/// A titled group of rows on one card — the course pages' replacement for a
/// grouped `List` section, so every course screen shares one look: Oggi's,
/// with its headings and the material the student chose for its cards.
struct CardSection<Content: View>: View {
    /// The section's heading, or `nil` for a card with none.
    var title: Text?
    /// An SF Symbol shown before the heading.
    var icon: String?
    /// A line of explanation below the card.
    var footer: LocalizedStringKey?
    /// The colour the icon is drawn in.
    var tint: Color = Theme.brand
    /// The content this view wraps.
    @ViewBuilder let content: Content

    /// Creates a section with a localised heading.
    ///
    /// - Parameters:
    ///   - title: The heading, or `nil` for none.
    ///   - icon: An SF Symbol shown before it.
    ///   - footer: A line of explanation below the card.
    ///   - tint: The colour the icon is drawn in.
    ///   - content: The card's rows.
    init(_ title: LocalizedStringKey? = nil, icon: String? = nil, footer: LocalizedStringKey? = nil,
         tint: Color = Theme.brand, @ViewBuilder content: () -> Content) {
        self.title = title.map { Text($0) }
        self.icon = icon
        self.footer = footer
        self.tint = tint
        self.content = content()
    }

    /// The view's content.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon).foregroundStyle(tint)
                    }
                    title
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lookCard()

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// Same, with a plain string title for data-driven headings.
extension CardSection {
    /// Creates a section whose heading is a plain string, for data-driven headings.
    ///
    /// - Parameters:
    ///   - title: The heading, used verbatim.
    ///   - icon: An SF Symbol shown before it.
    ///   - tint: The colour the icon is drawn in.
    ///   - content: The card's rows.
    init(verbatim title: String, icon: String? = nil, tint: Color = Theme.brand,
         @ViewBuilder content: () -> Content) {
        self.init(nil, icon: icon, tint: tint, content: content)
        self.title = Text(verbatim: title)
    }
}

/// A label and its value on one line of a card.
struct CardRow<Trailing: View>: View {
    /// The row's label.
    let label: String
    /// An SF Symbol shown before the label.
    var icon: String?
    /// The colour the icon is drawn in.
    var tint: Color = Theme.brand
    /// The `trailing` this view draws.
    @ViewBuilder let trailing: Trailing

    /// The view's content.
    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 22)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// A row whose value is plain text.
extension CardRow where Trailing == Text {
    /// Creates a row with a text value.
    ///
    /// - Parameters:
    ///   - label: The row's label.
    ///   - value: The value to show.
    ///   - icon: An SF Symbol shown before the label.
    ///   - tint: The colour the icon is drawn in.
    init(_ label: String, value: String, icon: String? = nil, tint: Color = Theme.brand) {
        self.init(label: label, icon: icon, tint: tint) { Text(value) }
    }
}

/// Free content padded like a card row.
struct CardBlock<Content: View>: View {
    /// The content this view wraps.
    @ViewBuilder let content: Content

    /// The view's content.
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
}

/// The hairline between card rows.
struct CardDivider: View {
    /// How far in from the leading edge the hairline starts.
    var inset: CGFloat = 14
    /// The view's content.
    var body: some View { Divider().padding(.leading, inset) }
}

/// Big numbers in small tiles: credits, hours, counts.
struct FactTiles: View {
    /// The tiles, each a big value over a small caption.
    let facts: [(value: String, label: String)]
    /// The colour the values are drawn in.
    var tint: Color = Theme.brand

    /// The values in the typeface of Oggi's date.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    /// The view's content.
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(spacing: 2) {
                    Text(fact.value)
                        .font(style.dateFont.font(size: 22, weight: style.dateWeight))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(fact.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .lookCard(cornerRadius: 20)
            }
        }
    }
}

/// A round initials badge for a person.
struct InitialsAvatar: View {
    /// The person's name, whose first two initials are drawn.
    let name: String
    /// The colour of the initials and of the circle behind them.
    var tint: Color = Theme.brand
    /// The badge's diameter.
    var size: CGFloat = 34

    /// The first letter of each of the first two words of ``name``, upper-cased.
    private var initials: String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    /// The view's content.
    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: .circle)
            .accessibilityHidden(true)
    }
}

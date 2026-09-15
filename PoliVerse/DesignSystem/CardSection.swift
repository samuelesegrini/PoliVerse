import SwiftUI

/// A titled group of rows on one card — the course pages' replacement for a
/// grouped `List` section, so every course screen shares one look.
struct CardSection<Content: View>: View {
    var title: Text?
    var icon: String?
    var footer: LocalizedStringKey?
    var tint: Color = Theme.brand
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey? = nil, icon: String? = nil, footer: LocalizedStringKey? = nil,
         tint: Color = Theme.brand, @ViewBuilder content: () -> Content) {
        self.title = title.map { Text($0) }
        self.icon = icon
        self.footer = footer
        self.tint = tint
        self.content = content()
    }

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
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()

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
    init(verbatim title: String, icon: String? = nil, tint: Color = Theme.brand,
         @ViewBuilder content: () -> Content) {
        self.init(nil, icon: icon, tint: tint, content: content)
        self.title = Text(verbatim: title)
    }
}

/// A label and its value on one line of a card.
struct CardRow<Trailing: View>: View {
    let label: String
    var icon: String?
    var tint: Color = Theme.brand
    @ViewBuilder let trailing: Trailing

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

extension CardRow where Trailing == Text {
    init(_ label: String, value: String, icon: String? = nil, tint: Color = Theme.brand) {
        self.init(label: label, icon: icon, tint: tint) { Text(value) }
    }
}

/// Free content padded like a card row.
struct CardBlock<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
}

/// The hairline between card rows.
struct CardDivider: View {
    var inset: CGFloat = 14
    var body: some View { Divider().padding(.leading, inset) }
}

/// Big numbers in small tiles: credits, hours, counts.
struct FactTiles: View {
    let facts: [(value: String, label: String)]
    var tint: Color = Theme.brand

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(spacing: 2) {
                    Text(fact.value)
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
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
                .cardBackground()
            }
        }
    }
}

/// A round initials badge for a person.
struct InitialsAvatar: View {
    let name: String
    var tint: Color = Theme.brand
    var size: CGFloat = 34

    private var initials: String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: .circle)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The scrolling, grouped ground every course subpage sits on.
    func courseScreen() -> some View {
        background(Color(.systemGroupedBackground))
    }
}

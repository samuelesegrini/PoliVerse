import SwiftUI

// The pieces every course page is built from, the same way the settings pages
// share theirs: a picture at the top that says what the page is about before a
// word is read, rows that start with a solid icon, and a bar for proportions.
// Colours come from a ramp around the course's own colour, so a course's pages
// are visibly one family, and each page is visibly the course's.

/// Colours around a course's own, checked against the look's page.
struct CourseRamp {
    let ramp: FlavorRamp

    init(course: Course, style: TodayStyle, scheme: ColorScheme) {
        self.init(index: course.colorSeed, style: style, scheme: scheme)
    }

    /// For a sitting or a lesson matched by name, as Oggi colours them.
    init(name: String, style: TodayStyle, scheme: ColorScheme) {
        self.init(index: TodayDigest.colourIndex(for: name), style: style, scheme: scheme)
    }

    private init(index: Int, style: TodayStyle, scheme: ColorScheme) {
        ramp = FlavorRamp(colour: Theme.courseAccentRGB(index, dark: scheme == .dark), style: style, scheme: scheme)
    }

    var mode: Flavor.Mode { ramp.mode }

    /// The course's colour itself, made readable on the page.
    var main: Flavor.RGB { ramp.colour(at: 0.3) }

    /// `count` colours, deepest first.
    func colours(_ count: Int) -> [Flavor.RGB] { ramp.colours(count) }

    /// A colour for the n-th of `count` things.
    func colour(_ index: Int, of count: Int) -> Flavor.RGB {
        ramp.colour(at: count > 1 ? Double(index) / Double(count - 1) : 0.3)
    }

    var neutral: Flavor.RGB { ramp.neutral }
}

/// A page's picture and headline: one thing in front with what stands behind
/// it, a title, and one line saying where things are.
struct CoursePageHero: View {
    let tiles: [HeroTile]
    let placeholder: HeroTile
    let title: Text
    var summary: Text?
    var badge: HeroBadge?
    let mode: Flavor.Mode

    var body: some View {
        VStack(spacing: 14) {
            HeroTileStack(tiles: tiles, placeholder: placeholder, badge: badge, mode: mode)
                .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                title
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let summary {
                    summary
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }
}

/// The solid icon at the start of a course page's row.
struct CourseRowTile: View {
    let symbol: String
    let colour: Flavor.RGB
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

    var body: some View {
        GlassTile(symbol: symbol, colour: colour, side: side)
            .accessibilityHidden(true)
    }
}

/// Parts of a whole on one bar, with a legend under it.
struct ShareBar: View {
    struct Segment: Identifiable {
        let id: String
        let title: String
        let colour: Color
        let value: Double
    }

    let segments: [Segment]
    var neutral: Color = .secondary

    private var total: Double { segments.reduce(0) { $0 + $1.value } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.colour.gradient)
                            .frame(width: max((geometry.size.width - CGFloat(segments.count - 1) * 2)
                                                * segment.value / max(total, 1), 3))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 14)
            .background(neutral.opacity(0.25))
            .clipShape(.capsule)

            FlowLegend(segments: segments, total: total)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(segments.map { "\($0.title) \(Int(($0.value / max(total, 1) * 100).rounded()))%" }
            .joined(separator: ", ")))
    }
}

private struct FlowLegend: View {
    let segments: [ShareBar.Segment]
    let total: Double

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }
            VStack(alignment: .leading, spacing: 6) { items }
        }
    }

    @ViewBuilder
    private var items: some View {
        ForEach(segments) { segment in
            HStack(spacing: 6) {
                Circle().fill(segment.colour).frame(width: 8, height: 8)
                Text(segment.title).font(.caption).foregroundStyle(.primary)
                Text("\(Int((segment.value / max(total, 1) * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// A few numbers side by side on one card, each large in the typeface of
/// Oggi's date with a word under it: what a page is about, at a glance.
struct GlanceStrip: View {
    struct Item: Identifiable {
        let id: String
        let value: String
        let label: String
    }

    let items: [Item]
    let tint: Color

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(.quaternary).frame(width: 1).padding(.vertical, 14)
                }
                VStack(spacing: 2) {
                    Text(item.value)
                        .font(style.dateFont.font(size: 28, weight: style.dateWeight))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .lookCard()
    }
}

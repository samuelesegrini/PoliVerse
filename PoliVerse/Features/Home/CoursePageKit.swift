import SwiftUI

// The pieces every course page is built from, the same way the settings pages
// share theirs: a picture at the top that says what the page is about before a
// word is read, rows that start with a solid icon, and a bar for proportions.
// Colours come from a ramp around the course's own colour, so a course's pages
// are visibly one family, and each page is visibly the course's.

/// Colours around a course's own, checked against the look's page.
struct CourseRamp {
    /// The look's ramp built around the course's colour.
    let ramp: FlavorRamp

    /// Colours for one course's pages.
    ///
    /// - Parameters:
    ///   - course: The course, whose ``Course/colorSeed`` picks the hue.
    ///   - style: The look in use.
    ///   - scheme: Light or dark.
    init(course: Course, style: TodayStyle, scheme: ColorScheme) {
        self.init(index: course.colorSeed, style: style, scheme: scheme)
    }

    /// For a sitting or a lesson matched by name, as Oggi colours them.
    init(name: String, style: TodayStyle, scheme: ColorScheme) {
        self.init(index: TodayDigest.colourIndex(for: name), style: style, scheme: scheme)
    }

    /// Builds the ramp from a course-colour index.
    ///
    /// - Parameters:
    ///   - index: The index into ``Theme/courseAccents``.
    ///   - style: The look in use.
    ///   - scheme: Light or dark.
    private init(index: Int, style: TodayStyle, scheme: ColorScheme) {
        ramp = FlavorRamp(colour: Theme.courseAccentRGB(index, dark: scheme == .dark), style: style, scheme: scheme)
    }

    /// How the look asks its surfaces to be drawn.
    var mode: Flavor.Mode { ramp.mode }

    /// The course's colour itself, made readable on the page.
    var main: Flavor.RGB { ramp.colour(at: 0.3) }

    /// `count` colours, deepest first.
    func colours(_ count: Int) -> [Flavor.RGB] { ramp.colours(count) }

    /// A colour for the n-th of `count` things.
    func colour(_ index: Int, of count: Int) -> Flavor.RGB {
        ramp.colour(at: count > 1 ? Double(index) / Double(count - 1) : 0.3)
    }

    /// The ramp's uncoloured end, for things the course does not own.
    var neutral: Flavor.RGB { ramp.neutral }
}

/// A page's headline, as the exam page opens: one glass tile in the middle
/// with the page's symbol, a title, and one line saying where things are.
struct CoursePageHero: View {
    /// The tiles to draw, the first of which is the one in front.
    let tiles: [HeroTile]
    /// What to draw when ``tiles`` is empty.
    let placeholder: HeroTile
    /// The page's title.
    let title: Text
    /// One line under the title saying where things stand.
    var summary: Text?
    /// A small mark on the tile's corner, such as a pass or a warning.
    var badge: HeroBadge?
    /// How the look asks the tile to be drawn.
    let mode: Flavor.Mode

    /// Scaled, so the tile grows with the reader's text.
    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 104

    /// The view's content.
    var body: some View {
        let front = tiles.first ?? placeholder
        VStack(spacing: 14) {
            GlassTile(symbol: front.symbol, colour: front.colour, side: side, surface: .glass, mode: mode)
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Image(systemName: badge.symbol)
                            .font(.system(size: side * 0.14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: side * 0.3, height: side * 0.3)
                            .background(badge.tint.gradient, in: .circle)
                            .offset(x: side * 0.08, y: side * 0.08)
                    }
                }
                .padding(.bottom, 4)
                .accessibilityHidden(true)
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

/// The symbol at the start of a course page's row, in the course's colour.
struct CourseRowTile: View {
    /// The row's SF Symbol.
    let symbol: String
    /// The course's colour, as the ramp makes it readable.
    let colour: Flavor.RGB
    /// The `side`, scaled with the reader's text size.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

    /// The view's content.
    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(colour.color)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// Parts of a whole on one bar, with a legend under it.
struct ShareBar: View {
    /// One part of the whole.
    struct Segment: Identifiable {
        /// The segment's identity.
        let id: String
        /// What the segment is called in the legend.
        let title: String
        /// The segment's colour.
        let colour: Color
        /// The segment's share, in whatever unit the caller counts in.
        let value: Double
    }

    /// The parts, in the order they are drawn.
    let segments: [Segment]
    /// What the bar is filled with when the segments add up to nothing.
    var neutral: Color = .secondary

    /// The segments' values added up, which the percentages are taken against.
    private var total: Double { segments.reduce(0) { $0 + $1.value } }

    /// The view's content.
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

/// The bar's legend: a dot, a name and a percentage per segment, on one row where it fits and stacked where it does not.
private struct FlowLegend: View {
    /// The segments to name.
    let segments: [ShareBar.Segment]
    /// The segments' values added up, which the percentages are taken against.
    let total: Double

    /// The view's content.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }
            VStack(alignment: .leading, spacing: 6) { items }
        }
    }

    /// One entry per segment, laid out by whichever arrangement fits.
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
    /// One figure and the word under it.
    struct Item: Identifiable {
        /// The item's identity.
        let id: String
        /// The figure, already formatted.
        let value: String
        /// What the figure counts.
        let label: String
    }

    /// The figures, left to right.
    let items: [Item]
    /// The colour the figures are drawn in.
    let tint: Color

    /// The look in use, whose date typeface the figures are set in.
    @Environment(\.look) private var style

    /// The view's content.
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(.quaternary).frame(width: 1).padding(.vertical, 14)
                }
                VStack(spacing: 2) {
                    Text(item.value)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
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

// MARK: - Look lists

/// Lists and rows drawn on the look's own material.
extension View {
    /// A `List` in the look in use: grouped sections, spaced as the look's
    /// pages are. Each `Section` asks for its own surface with ``lookRow()``,
    /// because a `listRowBackground` set here, on the `List`, does not reach
    /// the rows.
    func lookList() -> some View {
        listStyle(.insetGrouped)
            .listSectionSpacing(18)
    }

    /// The look's material behind a row, for the rows a list builds in its own
    /// sections.
    func lookRow() -> some View {
        listRowBackground(LookRowBackground())
    }
}

/// The surface of a list row: the look's material, squared off to the cell.
///
/// A cell has no corners of its own to round — the list rounds the group — so
/// the material is drawn at radius zero and the section's shape does the rest.
///
/// The rectangle is clear on purpose: any fill would sit *in front* of the
/// material and hide it. The material draws behind, and the rectangle is only
/// there to give it the cell's full size.
struct LookRowBackground: View {
    /// The view's content.
    var body: some View {
        Rectangle()
            .fill(.clear)
            .lookCard(cornerRadius: 0)
    }
}

/// A page's opening, as the exam page and the course pages have it: one glass
/// tile in the middle with the page's symbol, a title, and one line saying
/// where things are. Coloured from the look's own ramp, stable per symbol.
struct PageHero: View {
    /// The SF Symbol drawn in the tile, which also picks its colour.
    let symbol: String
    /// The page's title.
    let title: Text
    /// One line under the title saying where things stand.
    var summary: Text?
    /// A small mark on the tile's corner.
    var badge: HeroBadge?

    /// The look in use, which supplies the ramp.
    @Environment(\.look) private var style
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme

    /// The view's content.
    var body: some View {
        let ramp = FlavorRamp(style: style, scheme: scheme)
        CoursePageHero(
            tiles: [HeroTile(id: symbol, symbol: symbol,
                             colour: ramp.colour(at: 0.15 + Double(TodayDigest.colourIndex(for: symbol)) / 10))],
            placeholder: HeroTile(id: "empty", symbol: symbol, colour: ramp.neutral),
            title: title, summary: summary, badge: badge, mode: ramp.mode)
    }

    /// The hero as the first row of a list: no card, no separator, edge to edge.
    func listHeader() -> some View {
        self
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
    }
}

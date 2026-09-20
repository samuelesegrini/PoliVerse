import SwiftUI

// The band of line art under a page's title, and the one hand every page's
// band is drawn in.
//
// Every page past Oggi opened the same way: a title, then the list. Which
// means they were distinguishable only by their contents — and the top of a
// page is what a student sees first, and what stays longest, since it is the
// part the bar keeps once the list has scrolled underneath it.
//
// So a page draws a figure of its own, made of what that page is about: Corsi
// draws the week's teaching hours, Carriera draws the marks in the libretto.
// Different figures, one hand. Every band is the same height, sits on the same
// hairline, uses the same stroke and spacing, animates in with the same spring
// and takes its colour from the look the student chose. A page is recognisable
// at a glance without being a page from another app.
//
// What a band is **not** is decoration. ``LookPage`` leaves Oggi's paper and
// stickers behind deliberately — the pages past it are dense, and a pattern
// behind small secondary text is noise. So every mark in a band is a number
// the page has already loaded, no band is drawn when there is nothing to draw,
// and none of them invents a shape to fill the space.

/// The measurements every figure is drawn to, so that two figures made of
/// different things are still visibly made by the same hand.
enum FigureMetrics {
    /// The drawing height, above the baseline. Tall enough for a shape to have
    /// a shape; short enough that the list still starts above the fold.
    static let height: CGFloat = 54
    /// The width of a single mark — a day's column, an exam's tick.
    static let stroke: CGFloat = 7
    /// Between marks. A quarter of the stroke reads as a run rather than as
    /// separate objects.
    static let gap: CGFloat = 4
    /// The shortest a mark may be drawn: below this a value stops reading as a
    /// value and starts reading as a speck of dust.
    static let minimumMark: CGFloat = 4
    /// Between the title and the band.
    static let titleGap: CGFloat = 18

    static var markShape: RoundedRectangle { RoundedRectangle(cornerRadius: stroke / 2, style: .continuous) }
}

/// One page's figure: the marks, the hairline they stand on, and an optional
/// row of labels beneath it.
///
/// The caller supplies the marks. This supplies everything that has to be the
/// same everywhere — the height, the baseline, the way it arrives, and the one
/// sentence VoiceOver reads instead of forty unlabelled rectangles.
struct HeaderFigure<Content: View, Caption: View>: View {
    /// What the figure says, in words. The band is a single accessibility
    /// element: a student using VoiceOver wants "ventidue ore questa
    /// settimana", not twenty-two anonymous shapes.
    let summary: Text
    @ViewBuilder var content: Content
    @ViewBuilder var caption: Caption

    var body: some View {
        // No spacing above the rule: the marks stand *on* the baseline. A gap
        // there, however small, left every figure floating a few points over
        // its own ground line, which reads as a mistake rather than as air.
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(height: FigureMetrics.height, alignment: .bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Only the marks grow. Scaling the rule and the caption with
                // them would squash the caption's text on the way in.
                .figureEntrance()
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
            caption
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }
}

extension View {
    /// The one way a figure arrives: growing out of its own baseline, once.
    ///
    /// Lives apart from ``HeaderFigure`` because not every figure sits in a
    /// band — the libretto's marks are inside a card, with no rule under them
    /// — and the entrance is the part that has to be the same either way.
    func figureEntrance() -> some View {
        modifier(FigureEntrance())
    }
}

private struct FigureEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Once, on first appearance — the page's one piece of delight, at the
    /// frequency delight is allowed.
    @State private var drawn = false

    func body(content: Content) -> some View {
        content
            // Scaled, not resized: animating the height would relayout the
            // whole page on every frame of the entrance.
            .scaleEffect(y: drawn ? 1 : 0.12, anchor: .bottom)
            .opacity(drawn ? 1 : 0)
            .onAppear {
                guard !drawn else { return }
                // Reduce Motion keeps the fade and drops the growth: the
                // information is in the marks, never in the way they arrive.
                withAnimation(reduceMotion ? .easeOut(duration: 0.25)
                                           : .spring(duration: 0.55, bounce: 0.18)) {
                    drawn = true
                }
            }
    }
}

extension HeaderFigure where Caption == EmptyView {
    init(summary: Text, @ViewBuilder content: () -> Content) {
        self.summary = summary
        self.content = content()
        caption = EmptyView()
    }
}

/// A horizontal rule the width of whatever it is put in.
nonisolated struct FigureRule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// A page's opening: its title in the look's typeface, and its figure.
///
/// The two are one type rather than two lines at each call site so that the
/// gap between them, and the decision that the figure comes *after* the title
/// rather than behind it, are made once for the whole app.
struct LookHeader<Figure: View>: View {
    private let title: LocalizedStringKey
    private let subtitle: Text?
    private let figure: Figure

    init(_ title: LocalizedStringKey, subtitle: Text? = nil, @ViewBuilder figure: () -> Figure) {
        self.title = title
        self.subtitle = subtitle
        self.figure = figure()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FigureMetrics.titleGap) {
            LookTitle(title, subtitle: subtitle)
            figure
        }
    }
}

extension View {
    /// The page's name moves into the bar once the big title has scrolled
    /// under it — the same threshold and the same curve on every page, so that
    /// however differently two pages open, they end up in the same place.
    ///
    /// Belongs on the `ScrollView` itself: it reads that scroll view's
    /// geometry.
    func collapsingTitle(_ title: LocalizedStringKey) -> some View {
        modifier(CollapsingTitle(title: title))
    }
}

private struct CollapsingTitle: ViewModifier {
    let title: LocalizedStringKey
    @State private var inBar = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 70
            } action: { _, past in
                guard past != inBar else { return }
                withAnimation(.snappy(duration: 0.2)) { inBar = past }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .opacity(inBar ? 1 : 0)
                        .accessibilityHidden(!inBar)
                }
            }
    }
}

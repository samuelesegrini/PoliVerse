import SwiftUI

/// A panel resting at the bottom of the screen that the student drags between
/// three heights, like the one in Maps.
///
/// Drawn in the page rather than presented as a sheet: a presented sheet
/// would block the navigation bar's own sheets and popover while it is up.
///
/// The panel keeps its full height and slides; only its offset animates.
/// Resizing it instead re-laid out the list inside on every frame, and the
/// drag snapped back to zero before the release animation started.
struct BottomPanel<Content: View, Accessory: View>: View {
    enum Detent: CaseIterable {
        case peek, half, full

        func visibleHeight(in total: CGFloat) -> CGFloat {
            switch self {
            case .peek: 96
            case .half: total * 0.5
            case .full: total - 24
            }
        }
    }

    @Binding var detent: Detent
    @ViewBuilder var content: Content
    /// Rides on top of the panel's edge, like the tab bar accessory; hidden
    /// once the panel fills the screen.
    @ViewBuilder var accessory: Accessory

    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let total = proxy.size.height + proxy.safeAreaInsets.bottom
            let full = Detent.full.visibleHeight(in: total)
            // How much of the panel shows, following the finger with a little
            // give past the ends.
            let visible = rubberBand(detent.visibleHeight(in: total) - drag,
                                     min: Detent.peek.visibleHeight(in: total), max: full)

            ZStack(alignment: .top) {
                panel(total: total)
                    .frame(height: full)
                    .offset(y: full - visible)

                accessory
                    .offset(y: full - visible - 64)
                    .opacity(detent == .full ? 0 : 1)
                    .allowsHitTesting(detent != .full)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .frame(height: full, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func panel(total: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture { settle(on: detent == .peek ? .half : .peek) }
                .accessibilityLabel("Pannello")
                .accessibilityHint(detent == .peek ? "Espandi" : "Riduci")

            content
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34))
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in drag = value.translation.height }
                .onEnded { value in
                    let projected = detent.visibleHeight(in: total) - value.predictedEndTranslation.height
                    let nearest = Detent.allCases.min {
                        abs($0.visibleHeight(in: total) - projected) < abs($1.visibleHeight(in: total) - projected)
                    } ?? detent
                    settle(on: nearest)
                }
        )
    }

    /// The detent and the drag change in one animation, so the panel glides
    /// from under the finger to its resting place.
    private func settle(on target: Detent) {
        withAnimation(.spring(duration: 0.45, bounce: 0.12)) {
            detent = target
            drag = 0
        }
    }

    private func rubberBand(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        if value < lower { return lower - (lower - value) * 0.25 }
        if value > upper { return upper + (value - upper) * 0.25 }
        return value
    }
}

extension BottomPanel where Accessory == EmptyView {
    init(detent: Binding<Detent>, @ViewBuilder content: () -> Content) {
        self.init(detent: detent, content: content, accessory: { EmptyView() })
    }
}

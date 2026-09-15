import SwiftUI

/// A panel resting at the bottom of the screen that the student drags between
/// three heights, like the one in Maps.
///
/// Drawn in the page rather than presented as a sheet: a presented sheet
/// would block the navigation bar's own sheets and popover while it is up.
struct BottomPanel<Content: View>: View {
    enum Detent: CaseIterable {
        case peek, half, full

        func height(in total: CGFloat) -> CGFloat {
            switch self {
            case .peek: 96
            case .half: total * 0.5
            case .full: total - 24
            }
        }
    }

    @Binding var detent: Detent
    @ViewBuilder var content: Content

    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let total = proxy.size.height
            let height = max(Detent.peek.height(in: total) - 30,
                             min(detent.height(in: total) - drag, Detent.full.height(in: total) + 20))

            VStack(spacing: 0) {
                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .onTapGesture { withAnimation(.snappy) { detent = detent == .peek ? .half : .peek } }
                    .accessibilityLabel("Pannello")
                    .accessibilityHint(detent == .peek ? "Espandi" : "Riduci")

                content
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34))
            .gesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        let projected = detent.height(in: total) - value.predictedEndTranslation.height
                        let nearest = Detent.allCases.min {
                            abs($0.height(in: total) - projected) < abs($1.height(in: total) - projected)
                        } ?? detent
                        withAnimation(.spring(duration: 0.4, bounce: 0.15)) { detent = nearest }
                    }
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

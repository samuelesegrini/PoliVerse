import SwiftUI

/// Carries Oggi's page from one day to the next: the day leaving slides out
/// the way the calendar moved, the day arriving comes in behind it.
///
/// The shown day is held here rather than read straight from the shell so the
/// direction is decided before the change animates — read from `onChange` the
/// slide had already started, and every day arrived from the same side.
struct DayTransition<Content: View>: View {
    let day: Date
    @ViewBuilder let content: (Date) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Date?
    /// True while moving forwards in time; decides which edge each half uses.
    @State private var forwards = true

    private var transition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forwards ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forwards ? .leading : .trailing).combined(with: .opacity))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content(shown ?? day)
                .id(shown ?? day)
                .transition(transition)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: day) { old, new in
            forwards = new >= old
            withAnimation(.snappy(duration: 0.35)) { shown = new }
        }
        .onAppear { shown = day }
    }
}

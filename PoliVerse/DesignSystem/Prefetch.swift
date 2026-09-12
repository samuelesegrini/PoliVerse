import SwiftUI

/// Warms what the user is about to reach.
///
/// `onScrollTargetVisibilityChange` (iOS 18) reports which rows are on screen
/// as they change, which is the signal this needs: everything before it —
/// `onAppear` per row, or a visible-range guess from a `GeometryReader` — was
/// either too late or fired for rows that scrolled past in a flick.
///
/// The margin is what makes it feel instant: warming only what is visible is
/// warming what the user is already looking at, which is too late to help.
struct PrefetchModifier<ID: Hashable & Sendable>: ViewModifier {
    let ids: [ID]
    /// How many rows either side of the visible window to warm.
    let margin: Int
    let prefetch: ([ID]) -> Void

    func body(content: Content) -> some View {
        content.onScrollTargetVisibilityChange(idType: ID.self) { visible in
            guard !visible.isEmpty else { return }
            let indices = visible.compactMap { ids.firstIndex(of: $0) }
            guard let first = indices.min(), let last = indices.max() else { return }

            let lower = max(0, first - margin)
            let upper = min(ids.count - 1, last + margin)
            guard lower <= upper else { return }

            // Only what is not already visible: the rows on screen have been
            // asked for by their own views already.
            let window = Array(ids[lower...upper]).filter { !visible.contains($0) }
            guard !window.isEmpty else { return }
            prefetch(window)
        }
    }
}

extension View {
    /// Warms resources for rows just off screen as the user scrolls.
    ///
    /// Requires the rows to carry `.id(...)` matching `ids`, which is what
    /// `ForEach` over `Identifiable` gives for free.
    func prefetching<ID: Hashable & Sendable>(
        _ ids: [ID],
        margin: Int = 6,
        perform prefetch: @escaping ([ID]) -> Void
    ) -> some View {
        modifier(PrefetchModifier(ids: ids, margin: margin, prefetch: prefetch))
    }
}

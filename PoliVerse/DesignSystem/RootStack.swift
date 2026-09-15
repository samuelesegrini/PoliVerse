import SwiftUI

/// A root screen's navigation stack, left out when the screen is shown inside
/// a stack already: a tab of the new interface that adds its own buttons, or
/// a row of the single page's panel that pushes it.
struct RootStack<Content: View>: View {
    let embedded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }
}

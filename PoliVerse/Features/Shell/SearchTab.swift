import SwiftUI

/// Cerca: one field over everything, and before a search the places that are
/// not tabs. Its search role lets the tab bar float it apart from the others.
struct SearchTab: View {
    @Environment(\.shell) private var shell

    var body: some View {
        NavigationStack(path: Binding(get: { shell.searchPath }, set: { shell.searchPath = $0 })) {
            SearchView(embedded: true, places: NewDestination.inSearch)
                .profileButton()
                .dataStatusLine()
        }
    }
}

/// Whether opening Cerca puts the cursor in the field straight away.
///
/// On by default, as Apple's apps do. Off, the tab opens on its page — the
/// kinds, the recents, the places — and the keyboard comes up only when the
/// field is tapped: better for a student who opens Cerca to browse the places
/// rather than to type. SwiftUI offers exactly these two behaviours
/// (`TabSearchActivation.searchTabSelection` and `.automatic`); iOS 27 adds no
/// other.
enum SearchTabKeyboard {
    static let storageKey = "searchTabOpensKeyboard"
}

#Preview("Cerca") {
    SearchTab().previewEnvironment()
}

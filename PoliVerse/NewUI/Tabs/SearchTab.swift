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

#Preview("Cerca") {
    SearchTab().previewEnvironment()
}

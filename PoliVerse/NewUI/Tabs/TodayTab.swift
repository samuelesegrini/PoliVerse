import SwiftUI

/// Oggi: the day's lessons, exams and deadlines under the shared
/// ``TodayBar``. In the single-page layout the same page hides the tab bar
/// and carries the ``SinglePagePanel``.
struct TodayTab: View {
    @Environment(\.shell) private var shell
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Namespace private var customize

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayLanding(day: shell.day, style: style)
                    // Personalizza grows out of the page itself.
                    .matchedTransitionSource(id: "oggi", in: customize)
                    .padding(.bottom, shell.singlePage ? 180 : 40)
            }
            .todayBar()
            .toolbarVisibility(shell.singlePage ? .hidden : .automatic, for: .tabBar)
            .fullScreenCover(isPresented: Binding(get: { shell.isCustomizing },
                                                  set: { shell.isCustomizing = $0 })) {
                CustomizeOggi()
                    .navigationTransition(.zoom(sourceID: "oggi", in: customize))
            }
        }
        .overlay {
            if shell.singlePage {
                SinglePagePanel()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

#Preview("Oggi") {
    TodayTab().previewEnvironment()
}

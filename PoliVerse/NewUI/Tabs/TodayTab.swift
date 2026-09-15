import SwiftUI

/// Oggi: the day's lessons, exams and deadlines under the shared
/// ``TodayBar``. In the single-page layout the same page hides the tab bar
/// and carries the ``SinglePagePanel``.
struct TodayTab: View {
    @Environment(\.shell) private var shell
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    var body: some View {
        NavigationStack {
            ScrollView {
                TodayLanding(day: shell.day, style: style)
                    .padding(.bottom, shell.singlePage ? 180 : 40)
            }
            .todayBar()
            .toolbarVisibility(shell.singlePage ? .hidden : .automatic, for: .tabBar)
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

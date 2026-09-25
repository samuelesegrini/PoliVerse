import SwiftUI
import WidgetKit

/// Everything PoliVerse puts on a watch face and in the Smart Stack.
///
/// Like the phone's widgets, a separate process with no session and no
/// network. It reads only the snapshot the Watch app kept in the Watch's app
/// group, and draws a whole timeline from it at once, so the face moves from
/// one lecture to the next with neither the app nor the phone running.
@main
struct PoliVerseWatchWidgetBundle: WidgetBundle {
    /// The declaration's content.
    var body: some Widget {
        WatchNextLectureWidget()
        WatchRelevantLectureWidget()
    }
}

extension WatchSnapshot.Entry {
    /// A lecture for placeholders and previews.
    static let sample = WatchSnapshot.Entry(
        id: 0, title: "Analisi Matematica 1", room: "B.2.3",
        start: .now.addingTimeInterval(-1800), end: .now.addingTimeInterval(3600),
        isExam: false)

    /// The symbol for the entry's kind.
    var symbol: String { isExam ? "pencil.and.list.clipboard" : "person.bubble" }
}

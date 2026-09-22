import SwiftUI
import WidgetKit

/// Everything PoliVerse puts on the Home and Lock Screens.
///
/// A widget extension is a separate process with no session: it cannot sign
/// in, cannot reach the Keychain, and cannot call the Politecnico. It reads
/// only what the app has already written into the shared App Group container.
/// That constraint decides the whole design — a widget shows what was last
/// fetched, and says how old it is rather than pretending otherwise.
@main
struct PoliVerseWidgetBundle: WidgetBundle {
    /// The declaration's content.
    var body: some Widget {
        NextLectureWidget()
        TodayWidget()
        CareerWidget()
        FreeRoomsWidget()
        LectureLiveActivity()
        FreeRoomsControl()
        TimetableControl()
        CareerControl()
    }
}

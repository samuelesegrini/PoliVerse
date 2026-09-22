import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, the Lock Screen buttons and the Action button.
///
/// These are shortcuts, not displays: a control has room for a glyph and a
/// couple of words, so the only honest thing to put there is "take me
/// straight to the thing I open the app for anyway".
struct FreeRoomsControl: ControlWidget {
    /// The Control Centre button that opens free rooms.
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "control.freeRooms") {
            ControlWidgetButton(action: OpenFreeRoomsIntent()) {
                Label("Aule libere", systemImage: "building.2")
            }
        }
        .displayName("Aule libere")
        .description("Apre le aule libere adesso.")
    }
}

/// A Control Centre button that opens the timetable.
///
/// Its intent runs in this extension rather than in the app, so the destination travels
/// through the shared container — see ``AppDestination/send()``.
struct TimetableControl: ControlWidget {
    /// The Control Centre button that opens the timetable.
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "control.timetable") {
            ControlWidgetButton(action: OpenTimetableIntent()) {
                Label("Orario", systemImage: "calendar")
            }
        }
        .displayName("Orario")
        .description("Apre le lezioni di oggi.")
    }
}

/// A Control Centre button that opens the career.
struct CareerControl: ControlWidget {
    /// The Control Centre button that opens the career.
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "control.career") {
            ControlWidgetButton(action: OpenCareerIntent()) {
                Label("Carriera", systemImage: "graduationcap")
            }
        }
        .displayName("Carriera")
        .description("Apre media, CFU ed esami.")
    }
}

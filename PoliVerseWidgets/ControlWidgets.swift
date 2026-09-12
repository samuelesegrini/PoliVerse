import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, the Lock Screen buttons and the Action button.
///
/// These are shortcuts, not displays: a control has room for a glyph and a
/// couple of words, so the only honest thing to put there is "take me
/// straight to the thing I open the app for anyway".
struct FreeRoomsControl: ControlWidget {
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

struct TimetableControl: ControlWidget {
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

struct CareerControl: ControlWidget {
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

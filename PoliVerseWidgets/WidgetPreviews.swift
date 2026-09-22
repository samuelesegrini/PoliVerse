import ActivityKit
import SwiftUI
import WidgetKit

// Previews for every widget, in every family, in every state worth looking at.
//
// The `timeline:` form of `#Preview` is used throughout rather than
// `timelineProvider:`. The provider reads the App Group container, which in a
// preview is empty — so the real provider would render "accedi" for every
// widget and none of the layouts could be worked on at all. Handing the macro
// entries directly makes the *states* the thing being previewed, which is what
// a layout has to survive: a long course name, a missing room, an empty day,
// a stale cache.

// MARK: - Fixtures

/// Deliberately awkward: the shortest and longest real course names, rooms
/// with and without a building, and a title that has to wrap. A preview full
/// of tidy data proves nothing.
enum WidgetPreviewData {
    /// One lecture on today's date, for a preview.
    ///
    /// - Parameters:
    ///   - title: The lecture's name.
    ///   - hour: The hour it starts at.
    ///   - minute: The minute it starts at.
    ///   - lasting: How many hours it runs for.
    ///   - room: The room, or `nil` for a lecture with none.
    /// - Returns: The lecture.
    static func lecture(
        _ title: String = "Analisi Matematica 2",
        at hour: Int, _ minute: Int = 0, lasting: Double = 2,
        room: String? = "3.0.1"
    ) -> AgendaEvent {
        let start = Calendar.current.startOfDay(for: .now)
            .addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        return AgendaEvent(
            id: hour * 100 + minute, title: title,
            start: start, end: start.addingTimeInterval(lasting * 3600),
            kind: .lecture, room: room, roomAcronym: room)
    }

    /// A real course name long enough to wrap, so a layout is tested against one.
    static let longTitle =
        "Modelli e Metodi dell'Ottimizzazione Combinatoria per l'Ingegneria"

    /// A full day: four lectures, one with a long name, one with no room, at the hours the
    /// timetable actually uses.
    static var day: [AgendaEvent] {
        [lecture(at: 8, 15),
         lecture(longTitle, at: 10, 15, room: "Aula Rogers"),
         lecture("Fisica", at: 14, 15, lasting: 3, room: nil),
         lecture("Laboratorio", at: 17, 30, room: "L.26.02")]
    }

    /// A lecture that is always about to start, whenever the preview is opened.
    static var imminent: AgendaEvent {
        let start = Date.now.addingTimeInterval(900)
        return AgendaEvent(id: 1, title: "Analisi Matematica 2",
                           start: start, end: start.addingTimeInterval(7200),
                           kind: .lecture, room: "Aula Rogers", roomAcronym: "R.0.1")
    }

    /// A lecture already under way whenever the preview is opened.
    static var running: AgendaEvent {
        let start = Date.now.addingTimeInterval(-1800)
        return AgendaEvent(id: 2, title: WidgetPreviewData.longTitle,
                           start: start, end: start.addingTimeInterval(5400),
                           kind: .lecture, room: "3.0.1", roomAcronym: "3.0.1")
    }

    /// Today's snapshot for one campus, with nothing booked.
    static var freeRooms: FreeRoomsSnapshot {
        FreeRoomsSnapshot(day: .now, campus: "Milano Leonardo",
                          rooms: FreeRoomsSnapshot.previewRooms)
    }
}

// MARK: - Prossima lezione

#Preview("Prossima · small", as: .systemSmall) {
    NextLectureWidget()
} timeline: {
    NextLectureEntry(date: .now, lecture: WidgetPreviewData.imminent,
                     following: WidgetPreviewData.day[2], age: 60, signedIn: true)
    NextLectureEntry(date: .now, lecture: WidgetPreviewData.running,
                     following: nil, age: 60, signedIn: true)
    NextLectureEntry(date: .now, lecture: nil, following: nil,
                     age: 60, signedIn: true)
    NextLectureEntry(date: .now, lecture: nil, following: nil,
                     age: nil, signedIn: false)
    // Two days old: the only state where the widget admits its age.
    NextLectureEntry(date: .now, lecture: WidgetPreviewData.imminent,
                     following: nil, age: 172_800, signedIn: true)
}

#Preview("Prossima · medium", as: .systemMedium) {
    NextLectureWidget()
} timeline: {
    NextLectureEntry(date: .now, lecture: WidgetPreviewData.imminent,
                     following: WidgetPreviewData.day[1], age: 60, signedIn: true)
    NextLectureEntry(date: .now, lecture: WidgetPreviewData.running,
                     following: nil, age: 60, signedIn: true)
}

#Preview("Prossima · rettangolare", as: .accessoryRectangular) {
    NextLectureWidget()
} timeline: {
    NextLectureEntry(date: .now, lecture: WidgetPreviewData.imminent,
                     following: nil, age: 60, signedIn: true)
    NextLectureEntry(date: .now, lecture: WidgetPreviewData.running,
                     following: nil, age: 60, signedIn: true)
    NextLectureEntry(date: .now, lecture: nil, following: nil, age: nil, signedIn: false)
}

#Preview("Prossima · in linea", as: .accessoryInline) {
    NextLectureWidget()
} timeline: {
    NextLectureEntry(date: .now, lecture: WidgetPreviewData.imminent,
                     following: nil, age: 60, signedIn: true)
    NextLectureEntry(date: .now, lecture: nil, following: nil, age: 60, signedIn: true)
}

#Preview("Prossima · circolare", as: .accessoryCircular) {
    NextLectureWidget()
} timeline: {
    NextLectureEntry(date: .now, lecture: WidgetPreviewData.imminent,
                     following: nil, age: 60, signedIn: true)
    NextLectureEntry(date: .now, lecture: nil, following: nil, age: 60, signedIn: true)
}

// MARK: - Oggi

#Preview("Oggi · medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    // Mid-afternoon: two rows behind, two ahead. The state the layout is
    // really for, and the only one that shows the dimming.
    TodayEntry(date: WidgetPreviewData.lecture(at: 15).start,
               events: WidgetPreviewData.day, age: 300, signedIn: true)
    TodayEntry(date: .now, events: [], age: 300, signedIn: true)
    TodayEntry(date: .now, events: [], age: nil, signedIn: false)
    TodayEntry(date: WidgetPreviewData.lecture(at: 9).start,
               events: WidgetPreviewData.day, age: 200_000, signedIn: true)
}

#Preview("Oggi · large", as: .systemLarge) {
    TodayWidget()
} timeline: {
    TodayEntry(date: WidgetPreviewData.lecture(at: 15).start,
               events: WidgetPreviewData.day, age: 300, signedIn: true)
    TodayEntry(date: .now, events: [], age: 300, signedIn: true)
}

// MARK: - Carriera

#Preview("Carriera · small", as: .systemSmall) {
    CareerWidget()
} timeline: {
    CareerEntry(date: .now, snapshot: .preview, age: 600, signedIn: true)
    // A first-year with nothing recorded yet: the case where "0.0 / 110"
    // would be a confident lie.
    CareerEntry(date: .now,
                snapshot: CareerSnapshot(mean: 0, earnedCFU: 0, plannedCFU: 180,
                                         examsGiven: 0, examsPlanned: 28),
                age: 600, signedIn: true)
    CareerEntry(date: .now, snapshot: nil, age: nil, signedIn: false)
}

#Preview("Carriera · rettangolare", as: .accessoryRectangular) {
    CareerWidget()
} timeline: {
    CareerEntry(date: .now, snapshot: .preview, age: 600, signedIn: true)
}

#Preview("Carriera · circolare", as: .accessoryCircular) {
    CareerWidget()
} timeline: {
    CareerEntry(date: .now, snapshot: .preview, age: 600, signedIn: true)
}

// MARK: - Aule libere

#Preview("Aule · small", as: .systemSmall) {
    FreeRoomsWidget()
} timeline: {
    FreeRoomsEntry(date: .now, campus: "Milano Leonardo",
                   free: FreeRoomsSnapshot.previewRooms, total: 96, state: .ok)
    FreeRoomsEntry(date: .now, campus: "Milano Leonardo",
                   free: [], total: 96, state: .ok)
    FreeRoomsEntry(date: .now, campus: nil, free: [], total: 0, state: .noData)
    FreeRoomsEntry(date: .now, campus: "Milano Bovisa",
                   free: [], total: 0, state: .staleDay)
    FreeRoomsEntry(date: .now, campus: "Milano Leonardo",
                   free: [], total: 96, state: .closed)
}

#Preview("Aule · medium", as: .systemMedium) {
    FreeRoomsWidget()
} timeline: {
    FreeRoomsEntry(date: .now, campus: "Milano Leonardo",
                   free: FreeRoomsSnapshot.previewRooms, total: 96, state: .ok)
    FreeRoomsEntry(date: .now, campus: "Milano Leonardo",
                   free: [], total: 96, state: .closed)
}

#Preview("Aule · rettangolare", as: .accessoryRectangular) {
    FreeRoomsWidget()
} timeline: {
    FreeRoomsEntry(date: .now, campus: "Milano Leonardo",
                   free: FreeRoomsSnapshot.previewRooms, total: 96, state: .ok)
    FreeRoomsEntry(date: .now, campus: nil, free: [], total: 0, state: .noData)
}

// MARK: - Live Activity

/// The lecture the Live Activity previews are drawn for.
private let previewLecture = LectureActivityAttributes(
    title: "Analisi Matematica 2", room: "Aula Rogers", building: "Edificio 3",
    start: .now.addingTimeInterval(900),
    end: .now.addingTimeInterval(900 + 7200))

#Preview("Lezione · schermata di blocco", as: .content, using: previewLecture) {
    LectureLiveActivity()
} contentStates: {
    LectureActivityAttributes.ContentState(phase: .upcoming)
    LectureActivityAttributes.ContentState(phase: .running)
    LectureActivityAttributes.ContentState(phase: .ended)
}

#Preview("Lezione · isola espansa", as: .dynamicIsland(.expanded), using: previewLecture) {
    LectureLiveActivity()
} contentStates: {
    LectureActivityAttributes.ContentState(phase: .upcoming)
    LectureActivityAttributes.ContentState(phase: .running)
}

#Preview("Lezione · isola compatta", as: .dynamicIsland(.compact), using: previewLecture) {
    LectureLiveActivity()
} contentStates: {
    LectureActivityAttributes.ContentState(phase: .upcoming)
    LectureActivityAttributes.ContentState(phase: .ended)
}

#Preview("Lezione · isola minima", as: .dynamicIsland(.minimal), using: previewLecture) {
    LectureLiveActivity()
} contentStates: {
    LectureActivityAttributes.ContentState(phase: .running)
}

// MARK: - Controlli

// `#Preview(as:widget:)` has no ControlWidget form, so the controls are
// previewed as the views they actually are: a `Label` inside the same button
// the system draws. It checks the one thing that can go wrong here — a title
// too long for the tile, or a glyph that reads as something else.
#Preview("Controlli") {
    VStack(spacing: 12) {
        Label("Aule libere", systemImage: "building.2")
        Label("Orario", systemImage: "calendar")
        Label("Carriera", systemImage: "graduationcap")
    }
    .labelStyle(.titleAndIcon)
    .padding()
}

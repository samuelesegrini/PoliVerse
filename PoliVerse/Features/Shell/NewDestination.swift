import SwiftUI

/// The new interface's places besides Oggi, in one list both layouts use.
///
/// Each place lives in the tab whose question it answers
/// (`docs/information-architecture.md`, "una domanda per scheda"): Corsi and
/// Carriera are tabs of their own; the calendar opens from Oggi, the study
/// plan from Carriera, and the places and people — free rooms, the map, news,
/// notifications — are listed in Cerca. The single page lists them all in its panel.
nonisolated enum NewDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// The two places that are tabs of their own in the tab layout.
    case courses, career
    /// The places pushed inside a tab: the calendar in Oggi, the study plan in
    /// Carriera, the rest in Cerca.
    case calendar, freeRooms, map, studyPlan, news, notices

    /// The place's identity, which is its raw value.
    var id: String { rawValue }

    /// The tab a place lives in, in the tab layout.
    /// `CaseIterable` because the field metrics are split by tab, and the set
    /// of labels reported has to be this one rather than a copy that drifts.
    nonisolated enum Tab: String, CaseIterable, Hashable, Sendable {
        /// The four tabs of the tab layout.
        case today, courses, career, search
    }

    /// Which tab this place is reached through.
    var tab: Tab {
        switch self {
        case .courses: .courses
        case .career, .studyPlan: .career
        case .calendar: .today
        case .freeRooms, .map, .news, .notices: .search
        }
    }

    /// Whether the place is a tab itself, rather than a screen pushed inside one.
    var isTab: Bool { self == .courses || self == .career }

    /// The places Cerca lists before a search, in order.
    static var inSearch: [NewDestination] { allCases.filter { $0.tab == .search } }

    /// The single page's panel: every place.
    static var panel: [NewDestination] { allCases }

    /// What the place is called.
    var title: LocalizedStringKey {
        switch self {
        case .courses: "Corsi"
        case .career: "Carriera"
        case .calendar: "Calendario"
        case .freeRooms: "Aule libere"
        case .map: "Mappa"
        case .studyPlan: "Piano di studi"
        case .news: "Notizie"
        case .notices: "Notifiche"
        }
    }

    /// One line saying what is there.
    var detail: LocalizedStringKey {
        switch self {
        case .courses: "Materiali, avvisi e appelli"
        case .career: "Libretto, esami e media"
        case .calendar: "Settimana e mese"
        case .freeRooms: "Adesso e più tardi"
        case .map: "Campus ed edifici"
        case .studyPlan: "Piano e simulazione della media"
        case .news: "Notizie dall’ateneo"
        case .notices: "Comunicazioni per te"
        }
    }

    /// The place's SF Symbol.
    var systemImage: String {
        switch self {
        case .courses: "books.vertical"
        case .career: "graduationcap"
        case .calendar: "calendar"
        case .freeRooms: "door.left.hand.open"
        case .map: "map"
        case .studyPlan: "list.bullet.rectangle"
        case .news: "newspaper"
        case .notices: "megaphone"
        }
    }
}

/// Where a way in from outside (Siri, Shortcuts, Control Center, a
/// notification) lands in the new interface.
nonisolated enum NewRoute: Hashable, Sendable {
    /// Oggi, the landing page.
    case today
    /// Cerca, or the panel in the single-page layout.
    case search
    /// One of the places, opened directly.
    case destination(NewDestination)

    /// The route an outside entry point asks for.
    ///
    /// - Parameter destination: The destination named by Siri, Shortcuts, Control Center or a notification.
    init(_ destination: AppDestination) {
        switch destination {
        case .home: self = .today
        case .search: self = .search
        case .calendar: self = .destination(.calendar)
        case .weBeep: self = .destination(.courses)
        case .career, .simulator: self = .destination(.career)
        case .plan: self = .destination(.studyPlan)
        case .freeRooms: self = .destination(.freeRooms)
        case .map: self = .destination(.map)
        }
    }
}

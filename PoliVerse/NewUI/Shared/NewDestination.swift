import SwiftUI

/// The new interface's places besides Oggi, in one list both layouts use:
/// the tabs show Corsi and Carriera and list the rest in Cerca, the single
/// page lists them all in its panel. See `docs/information-architecture.md`.
nonisolated enum NewDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case courses, career
    case calendar, freeRooms, map, studyPlan, news, notices

    var id: String { rawValue }

    /// The tab a place lives in, in the tab layout.
    /// `CaseIterable` because the field metrics are split by tab, and the set
    /// of labels reported has to be this one rather than a copy that drifts.
    nonisolated enum Tab: String, CaseIterable, Hashable, Sendable {
        case today, courses, career, search
    }

    var tab: Tab {
        switch self {
        case .courses: .courses
        case .career: .career
        case .calendar, .freeRooms, .map, .studyPlan, .news, .notices: .search
        }
    }

    /// The places Cerca lists before a search, in order.
    static var inSearch: [NewDestination] { allCases.filter { $0.tab == .search } }

    /// The single page's panel: every place.
    static var panel: [NewDestination] { allCases }

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
    case today
    case search
    case destination(NewDestination)

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

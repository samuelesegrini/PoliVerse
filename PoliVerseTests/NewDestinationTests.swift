import Foundation
import Testing
@testable import PoliVerse

/// The new interface's one list of places: the same in both layouts, and the
/// landing spot for every way in from outside.
@Suite("New interface destinations")
struct NewDestinationTests {
    @Test("Both layouts reach the same places: tabs plus Cerca's list, or the panel")
    func sameInBothLayouts() {
        let tabs = Set(NewDestination.allCases.filter { $0.tab != .search })
        let inSearch = Set(NewDestination.inSearch)
        #expect(tabs.union(inSearch) == Set(NewDestination.panel))
        #expect(tabs.isDisjoint(with: inSearch))
        #expect(tabs == [.courses, .career])
    }

    @Test("Cerca lists the places that are not tabs, the calendar first")
    func searchList() {
        #expect(NewDestination.inSearch.first == .calendar)
        #expect(NewDestination.inSearch.allSatisfy { $0.tab == .search })
    }

    @Test("Every way in from outside lands somewhere in the new interface")
    func routing() {
        #expect(NewRoute(.home) == .today)
        #expect(NewRoute(.search) == .search)
        #expect(NewRoute(.calendar) == .destination(.calendar))
        #expect(NewRoute(.weBeep) == .destination(.courses))
        #expect(NewRoute(.career) == .destination(.career))
        #expect(NewRoute(.simulator) == .destination(.career))
        #expect(NewRoute(.plan) == .destination(.studyPlan))
        #expect(NewRoute(.freeRooms) == .destination(.freeRooms))
        #expect(NewRoute(.map) == .destination(.map))
    }

    @Test("Each place has a symbol")
    func labelled() {
        for destination in NewDestination.allCases {
            #expect(!destination.systemImage.isEmpty)
        }
    }
}

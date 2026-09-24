import Foundation
import Testing
@testable import PoliVerse

/// The new interface's one list of places: the same in both layouts, and the
/// landing spot for every way in from outside.
@Suite("New interface destinations")
struct NewDestinationTests {
    @Test("Both layouts reach the same places: each tab's own, or the panel")
    func sameInBothLayouts() {
        let tabs = Set(NewDestination.allCases.filter(\.isTab))
        #expect(tabs == [.courses, .career])
        // Every place lives in exactly one tab, and the panel lists them all.
        #expect(Set(NewDestination.allCases) == Set(NewDestination.panel))
    }

    @Test("Each place lives in the tab whose question it answers")
    func homes() {
        #expect(NewDestination.calendar.tab == .today)
        #expect(NewDestination.studyPlan.tab == .career)
        #expect(NewDestination.inSearch == [.freeRooms, .map, .news, .notices])
        #expect(NewDestination.inSearch.allSatisfy { $0.tab == .search && !$0.isTab })
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

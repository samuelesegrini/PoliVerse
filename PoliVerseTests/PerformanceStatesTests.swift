import Foundation
import Testing
@testable import PoliVerse

/// The labels the app reports to StateReporting, so hangs and hitches from the
/// field arrive attributed: "Carriera hitches", not "the app hitches".
///
/// Two rules Apple states and one this app learned. Theirs: a small, fixed set
/// of labels per domain — an unbounded set is what the state limit punishes —
/// and never an empty label, which is a fatal error. Ours: the set has to be
/// the tabs actually on screen. It was five labels from the previous
/// interface, kept long after students stopped seeing it, so every report was
/// filtered out and the field numbers came back split by nothing.
@MainActor
@Suite("Stati per le prestazioni")
struct PerformanceStatesTests {
    /// Taken from the tab enum rather than written out again, which is the
    /// point: a tab added to the interface is a label reported, without
    /// anybody remembering to come here.
    @Test("Le schede riportate sono quelle dell’interfaccia in uso")
    func labelsAreTheTabsOnScreen() {
        #expect(PerformanceStates.tabs == ["today", "courses", "career", "search"])
        #expect(PerformanceStates.tabs == Set(NewDestination.Tab.allCases.map(\.rawValue)))
    }

    /// The previous interface's five: none of them may come back, or the
    /// reports go back to being filtered out in silence.
    @Test("Le schede della vecchia interfaccia non sono più riportate")
    func theOldLabelsAreGone() {
        for old in ["home", "webeep", "calendar"] {
            #expect(!PerformanceStates.tabs.contains(old), "\(old) è una scheda che non esiste più")
        }
    }

    /// Apple's limit is on the number of distinct states, and an empty label
    /// is a crash rather than a missing one.
    @Test("Poche etichette, nessuna vuota")
    func boundedAndNonEmpty() {
        #expect(PerformanceStates.tabs.count <= 8, "Il limite di stati punisce un insieme che cresce")
        #expect(!PerformanceStates.tabs.contains(""), "Un’etichetta vuota è un errore fatale")
        #expect(PerformanceStates.tabs.allSatisfy { !$0.isEmpty })
    }

    /// Two domains, each a small fixed set, as Apple asks.
    @Test("I domini sono due, con il prefisso dell’app")
    func domains() {
        #expect(PerformanceStates.Domain.allCases.count == 2)
        #expect(PerformanceStates.Domain.allCases.allSatisfy { $0.rawValue.hasPrefix("one.wape.PoliVerse.") })
        #expect(PerformanceStates.Domain.tab.rawValue == "one.wape.PoliVerse.tab")
        #expect(PerformanceStates.Domain.data.rawValue == "one.wape.PoliVerse.data")
    }

    /// Reporting the same state twice spends a rate-limited budget for
    /// nothing, and reporting an unknown one must be a no-op rather than a new
    /// label. Neither is observable from outside, so this only pins that the
    /// calls are safe to make from anywhere in the app.
    @Test("Riportare una scheda sconosciuta, o la stessa due volte, non fa danni")
    func reportingIsSafe() {
        PerformanceStates.tabSelected("today")
        PerformanceStates.tabSelected("today")
        PerformanceStates.tabSelected("una scheda che non esiste")
        PerformanceStates.tabSelected(nil)
        PerformanceStates.dataSource(usesSampleData: true)
        PerformanceStates.dataSource(usesSampleData: true)
    }
}

import Foundation
import Testing
@testable import PoliVerse

/// The labels the app reports to StateReporting, so hangs and hitches from the
/// field arrive attributed: "Carriera hitches", not "the app hitches".
///
/// Two rules Apple states: a small, fixed set of labels per domain — an
/// unbounded set is what the state limit punishes — and never an empty label,
/// which is a fatal error.
///
/// One this app learned: the set has to cover the tabs actually on screen. It
/// was once the five of the previous interface alone, so everything the new
/// one reported was filtered out and the field numbers came back split by
/// nothing. Both interfaces ship — Impostazioni switches between them — so
/// both are in the set, and so is `single`, because the single page is a state
/// a student can sit in for a whole session.
@MainActor
@Suite("Stati per le prestazioni")
struct PerformanceStatesTests {
    /// The check that survives a change: the labels are written out by hand in
    /// `PerformanceStates`, so a tab added to ``NewDestination/Tab`` would
    /// otherwise be reported as no state at all, silently. That is what
    /// `CaseIterable` on that enum is for.
    @Test("Ogni scheda dell’interfaccia in uso ha la sua etichetta")
    func everyShippingTabIsReported() {
        for tab in NewDestination.Tab.allCases {
            #expect(PerformanceStates.tabs.contains(tab.rawValue),
                    "La scheda «\(tab.rawValue)» non verrebbe riportata al campo")
        }
    }

    /// Not a tab, but a state: in the single-page layout there is no tab bar,
    /// and a hitch there belongs to that layout rather than to Oggi.
    @Test("Anche la pagina unica è uno stato")
    func singlePageIsAState() {
        #expect(PerformanceStates.tabs.contains("single"))
    }

    /// The previous interface is still reachable from Impostazioni, so its
    /// tabs still report. Dropping them would blind the numbers for whoever
    /// switched back.
    @Test("Le schede della vecchia interfaccia riportano ancora, perché esiste ancora")
    func theOldInterfaceStillReports() {
        for old in ["home", "webeep", "calendar"] {
            #expect(PerformanceStates.tabs.contains(old))
        }
    }

    /// Apple's limit is on the number of distinct states, and an empty label
    /// is a crash rather than a missing one.
    @Test("Poche etichette, nessuna vuota")
    func boundedAndNonEmpty() {
        #expect(PerformanceStates.tabs.count <= 12, "Il limite di stati punisce un insieme che cresce")
        #expect(PerformanceStates.tabs.allSatisfy { !$0.isEmpty }, "Un’etichetta vuota è un errore fatale")
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

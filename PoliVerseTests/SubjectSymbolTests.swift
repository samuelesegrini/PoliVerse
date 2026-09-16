import Testing
import UIKit
@testable import PoliVerse

/// Course names to symbols: a symbol name that does not exist draws nothing,
/// and a rule in the wrong order gives a course another subject's icon.
@Suite("Subject symbol")
struct SubjectSymbolTests {
    @Test("Every symbol in the table exists")
    func symbolsExist() {
        for symbol in SubjectSymbol.rules.map(\.symbol) + [SubjectSymbol.fallback] {
            #expect(UIImage(systemName: symbol) != nil, "\(symbol)")
        }
    }

    @Test("Specific names win over general ones", arguments: [
        ("Basi di Dati", "cylinder.split.1x2"),
        ("Architetture dei Calcolatori e Sistemi Operativi", "cpu"),
        ("Fisica Tecnica", "thermometer.medium"),
        ("Fisica Sperimentale", "atom"),
        ("Analisi e Geometria 1", "function"),
        ("Ingegneria del Software", "chevron.left.forwardslash.chevron.right"),
        ("Probabilità e Statistica", "chart.bar"),
        ("Storia dell'Arte", "book.closed"),
    ])
    func matches(name: String, symbol: String) {
        #expect(SubjectSymbol.symbol(for: name) == symbol)
    }
}

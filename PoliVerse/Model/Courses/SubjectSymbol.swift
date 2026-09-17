import Foundation

/// An SF Symbol for a course, picked from the words in its name.
///
/// Politecnico course names are descriptive enough that a handful of Italian
/// and English stems cover most of them: "Analisi Matematica" is maths,
/// "Basi di Dati" is databases. Rules are tried in order, so the more specific
/// ones come first — "Fisica Tecnica" is engineering heat, not physics.
nonisolated enum SubjectSymbol {
    static let fallback = "book.closed"

    /// Stems, matched against the folded name, and the symbol they mean.
    static let rules: [(stems: [String], symbol: String)] = [
        (["basi di dati", "database", "data base", "sql"], "cylinder.split.1x2"),
        (["intelligenza artificiale", "machine learning", "apprendimento", "artificial intelligence", "neural"], "brain"),
        (["sicurezza informatica", "cybersecurity", "crittograf", "security"], "lock.shield"),
        (["reti di calcolatori", "reti logiche", "computer network", "internet", "network"], "network"),
        (["sistemi operativi", "architetture dei calcolatori", "calcolatori", "computer architecture"], "cpu"),
        (["ingegneria del software", "software engineering", "programmazione", "informatica", "algoritm",
          "computer science", "programming", "linguaggi", "strutture dati", "data structures"], "chevron.left.forwardslash.chevron.right"),
        (["fisica tecnica", "termodinamic", "termo", "thermo", "calore", "heat"], "thermometer.medium"),
        (["telecomunicazion", "segnali", "antenn", "signal", "wireless"], "antenna.radiowaves.left.and.right"),
        (["elettronic", "circuit", "electronic"], "memorychip"),
        (["elettrotecnic", "elettric", "energia", "energy", "power", "electric"], "bolt"),
        (["automatica", "controlli", "control"], "dial.medium"),
        (["probabilit", "statistic", "statistics"], "chart.bar"),
        (["analisi", "calculus", "matematic", "mathemat"], "function"),
        (["geometria", "algebra", "geometry"], "square.on.circle"),
        (["fisica", "physics", "quantist", "quantum"], "atom"),
        (["chimic", "chemistr"], "flask"),
        (["biolog", "bioingegneria", "biomedic", "biomed"], "leaf"),
        (["meccanic", "macchine", "mechanic", "robot"], "gearshape.2"),
        (["material", "struttur", "scienza delle costruzioni", "structural"], "cube"),
        (["fluid", "idraulic", "hydraul"], "drop"),
        (["aerospazial", "aeronautic", "aerospace", "volo", "flight"], "airplane"),
        (["architettura", "urbanistic", "edilizia", "building"], "building.columns"),
        (["disegno", "design", "rappresentazione", "drawing"], "pencil.and.ruler"),
        (["economi", "gestion", "finanz", "management", "business", "impresa"], "chart.line.uptrend.xyaxis"),
        (["ambient", "territorio", "environment", "sostenibil"], "globe.europe.africa"),
        (["trasport", "veicol", "transport", "vehicle"], "car"),
        (["inglese", "english", "lingua"], "character.bubble"),
        (["laboratorio", "laboratory", "lab "], "testtube.2"),
        (["progetto", "project", "tesi", "thesis"], "hammer"),
    ]

    static func symbol(for courseName: String) -> String {
        let folded = courseName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return rules.first { rule in rule.stems.contains { folded.contains($0) } }?.symbol ?? fallback
    }
}

import Foundation

/// Reads a PoliMi payload for the diagnostic screen.
///
/// The question it serves: does any service tell which degree course and
/// plan a matricola is enrolled in? Field names were guessed until now, and
/// only a real account can show them — so the screen lists every field, masks
/// the values by default (they are the student's records) and flags the ones
/// that could be the codes.
nonisolated enum PayloadInspector {
    struct Field: Sendable, Hashable, Identifiable {
        var id: String { path }
        let path: String
        let type: String
        /// The first non-empty value seen, unmasked; masked for display.
        let sample: String?
    }

    static func fields(in value: JSONValue) -> [Field] {
        var found: [String: Field] = [:]
        walk(value, path: "", into: &found)
        return found.values.sorted { $0.path < $1.path }
    }

    private static func walk(_ value: JSONValue, path: String, into found: inout [String: Field]) {
        switch value {
        case .object(let fields):
            for (key, child) in fields { walk(child, path: path.isEmpty ? key : "\(path).\(key)", into: &found) }
        case .array(let items):
            let childPath = path + "[]"
            if items.isEmpty { record(childPath, "array[0]", nil, &found) }
            for item in items { walk(item, path: childPath, into: &found) }
        case .string(let text): record(path, "string", text.isEmpty ? nil : text, &found)
        case .number(let number):
            record(path, "number", number == number.rounded() ? String(Int(number)) : String(number), &found)
        case .bool(let flag): record(path, "bool", String(flag), &found)
        case .null: record(path, "null", nil, &found)
        }
    }

    /// Keeps the first real type and sample: a field null in one element and
    /// a number in the next is a number.
    private static func record(_ path: String, _ type: String, _ sample: String?, _ found: inout [String: Field]) {
        if let existing = found[path], existing.type != "null", existing.sample != nil { return }
        let keptType = type == "null" ? (found[path]?.type ?? type) : type
        found[path] = Field(path: path, type: keptType, sample: sample ?? found[path]?.sample)
    }

    /// Letters become A or a, digits 9: "IT1" reads "AA9", enough to see a
    /// code's shape without the code.
    static func mask(_ text: String) -> String {
        String(text.map { character in
            if character.isNumber { return "9" }
            if character.isLetter { return character.isUppercase ? "A" : "a" }
            return character
        })
    }

    private static let hints = ["corso", "cds", "cdl", "indir", "piano", "classe", "k_cf", "scuola", "curricul",
                                "orient", "percorso", "pspa", "track", "degree", "programme", "program"]

    static func isInteresting(_ path: String) -> Bool {
        let key = (path.split(separator: ".").last.map(String.init) ?? path).lowercased()
        return hints.contains { key.contains($0) }
    }

    static func report(title: String, fields: [Field], showValues: Bool) -> String {
        let lines = fields.map { field in
            let sample = field.sample.map { " = " + (showValues ? $0 : mask($0)) } ?? ""
            return "  \(field.path): \(field.type)\(sample)\(isInteresting(field.path) ? "  ★" : "")"
        }
        return ([title] + lines).joined(separator: "\n")
    }

    /// Whether the exam's lecturer is among a scheda's, names as sets of words.
    static func sameLecturer(exam: String, scheda: [String]) -> Bool {
        let words = { (name: String) in
            Set(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
                .split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count > 1 })
        }
        let wanted = words(exam)
        guard !wanted.isEmpty else { return false }
        return scheda.map(words).contains { $0.intersection(wanted).count >= min(2, wanted.count) }
    }
}

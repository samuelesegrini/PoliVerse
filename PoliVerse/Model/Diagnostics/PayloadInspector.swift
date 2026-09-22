import Foundation

/// Reads a Politecnico payload for the diagnostics screen: every field, its type, and a
/// sample of its value.
///
/// Written to answer whether any service says which degree course and study plan a
/// matricola is enrolled in, which only a real account can show. Values are masked by
/// default — they are the student's records — and the fields that could carry those
/// codes are flagged by ``isInteresting(_:)``.
nonisolated enum PayloadInspector {
    /// One field found in a payload.
    struct Field: Sendable, Hashable, Identifiable {
        /// ``path``.
        var id: String { path }
        /// Where the field sits, with `[]` for an array level.
        let path: String
        /// The field's JSON type, taking the first non-null type seen.
        let type: String
        /// The first non-empty value seen, unmasked. ``report(title:fields:showValues:)`` masks
        /// it unless the student asked to see it.
        let sample: String?
    }

    /// Every field in a payload, by path.
    ///
    /// - Parameter value: The decoded payload.
    /// - Returns: The fields, sorted by path.
    static func fields(in value: JSONValue) -> [Field] {
        var found: [String: Field] = [:]
        walk(value, path: "", into: &found)
        return found.values.sorted { $0.path < $1.path }
    }

    /// Walks a payload, recording each leaf by its path.
    ///
    /// - Parameters:
    ///   - value: The value to walk.
    ///   - path: The path so far.
    ///   - found: The fields collected so far, updated in place.
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

    /// Records one field, keeping the first real type and sample: a field null in one
    /// element and a number in the next is a number.
    ///
    /// - Parameters:
    ///   - path: Where the field sits.
    ///   - type: Its JSON type here.
    ///   - sample: Its value here, if any.
    ///   - found: The fields collected so far, updated in place.
    private static func record(_ path: String, _ type: String, _ sample: String?, _ found: inout [String: Field]) {
        if let existing = found[path], existing.type != "null", existing.sample != nil { return }
        let keptType = type == "null" ? (found[path]?.type ?? type) : type
        found[path] = Field(path: path, type: keptType, sample: sample ?? found[path]?.sample)
    }

    /// A value with its letters replaced by `A` or `a` and its digits by `9`, so `"IT1"`
    /// reads `"AA9"` — enough to see a code's shape without the code.
    ///
    /// - Parameter text: The value to mask.
    /// - Returns: The masked value.
    static func mask(_ text: String) -> String {
        String(text.map { character in
            if character.isNumber { return "9" }
            if character.isLetter { return character.isUppercase ? "A" : "a" }
            return character
        })
    }

    /// Key fragments that suggest a field might carry a degree course or study plan code.
    private static let hints = ["corso", "cds", "cdl", "indir", "piano", "classe", "k_cf", "scuola", "curricul",
                                "orient", "percorso", "pspa", "track", "degree", "programme", "program"]

    /// Whether a field's own name suggests it carries a degree course or plan code.
    ///
    /// - Parameter path: The field's path. Only its last component is matched.
    /// - Returns: `true` when the name matches one of the hints.
    static func isInteresting(_ path: String) -> Bool {
        let key = (path.split(separator: ".").last.map(String.init) ?? path).lowercased()
        return hints.contains { key.contains($0) }
    }

    /// The fields as text, for copying out of the diagnostics screen.
    ///
    /// - Parameters:
    ///   - title: A heading for the payload.
    ///   - fields: The fields to list.
    ///   - showValues: Whether to print values as they are, rather than masked.
    /// - Returns: One line per field, with interesting ones starred.
    static func report(title: String, fields: [Field], showValues: Bool) -> String {
        let lines = fields.map { field in
            let sample = field.sample.map { " = " + (showValues ? $0 : mask($0)) } ?? ""
            return "  \(field.path): \(field.type)\(sample)\(isInteresting(field.path) ? "  ★" : "")"
        }
        return ([title] + lines).joined(separator: "\n")
    }

    /// Whether an exam's lecturer is among a teaching scheda's, compared as sets of words.
    ///
    /// Two names match when they share at least two words — or every word, for a one-word
    /// name — so initials, ordering and accents do not decide it.
    ///
    /// - Parameters:
    ///   - exam: The lecturer named on the sitting.
    ///   - scheda: The lecturers named on the scheda.
    /// - Returns: `true` when one of them is the same person.
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

import Foundation

/// Describes the *structure* of a JSON payload — its keys and their types —
/// without reproducing any of its content.
///
/// The notifications endpoint was known to exist (it answers 401) but its
/// response was never captured, so the decoder for it had to be written
/// against guesses. This turns one device run into the answer: the log says
/// what the payload actually looks like, and the decoder can be corrected
/// against fact instead of another guess.
///
/// - Important: keys and types only, never values. A notification's text is
///   the student's own mail — subject lines, names, exam results. It has no
///   business in a log that gets pasted into a chat, and describing the shape
///   does not need it.
nonisolated enum JSONShape {
    /// A one-line summary, e.g.
    /// `array[12] of object{data_inserimento: string, id_notice: number}`.
    static func describe(_ data: Data, maxKeys: Int = 40) -> String {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return "unparseable (\(data.count) bytes)"
        }
        return describe(value, maxKeys: maxKeys)
    }

    static func describe(_ value: JSONValue, maxKeys: Int = 40) -> String {
        switch value {
        case .null: return "null"
        case .bool: return "bool"
        case .number: return "number"
        case .string: return "string"
        case .array(let items):
            // One element stands for all of them: these payloads are
            // homogeneous lists, and printing every element would bury the
            // one thing being looked for.
            guard let first = items.first else { return "array[0]" }
            return "array[\(items.count)] of \(describe(first, maxKeys: maxKeys))"
        case .object(let fields):
            let described = fields.keys.sorted().prefix(maxKeys).map { key in
                "\(key): \(shallowType(fields[key] ?? .null))"
            }
            let suffix = fields.count > maxKeys ? ", …+\(fields.count - maxKeys)" : ""
            return "object{\(described.joined(separator: ", "))\(suffix)}"
        }
    }

    /// The type of a nested value, one level deep — enough to tell a string
    /// from an `{it, en}` pair without printing a whole tree.
    private static func shallowType(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool: return "bool"
        case .number: return "number"
        case .string: return "string"
        case .array(let items): return "array[\(items.count)]"
        case .object(let fields): return "object{\(fields.keys.sorted().joined(separator: ","))}"
        }
    }
}

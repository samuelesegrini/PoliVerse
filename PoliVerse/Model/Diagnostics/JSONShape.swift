import Foundation

/// Describes the structure of a JSON payload — its keys and their types — without
/// reproducing any of its content.
///
/// Used for the endpoints whose response has not been captured from a real account, so
/// that one device run replaces a guessed decoder with fact.
///
/// - Important: keys and types only, never values. A notification's text is the
///   student's own mail, and describing a shape does not need it.
nonisolated enum JSONShape {
    /// A one-line description of a payload's shape, for example
    /// `array[12] of object{data_inserimento: string, id_notice: number}`.
    ///
    /// - Parameters:
    ///   - data: The response body.
    ///   - maxKeys: How many of an object's keys to name before counting the rest.
    /// - Returns: The description, or a byte count when the body is not JSON.
    static func describe(_ data: Data, maxKeys: Int = 40) -> String {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return "unparseable (\(data.count) bytes)"
        }
        return describe(value, maxKeys: maxKeys)
    }

    /// A one-line description of a decoded value's shape.
    ///
    /// One element stands for a whole array: these payloads are homogeneous lists, and
    /// printing every element would bury what is being looked for.
    ///
    /// - Parameters:
    ///   - value: The decoded payload.
    ///   - maxKeys: How many of an object's keys to name before counting the rest.
    /// - Returns: The description.
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

    /// The type of a nested value, one level deep — enough to tell a string from an
    /// `{it, en}` pair without printing a whole tree.
    ///
    /// - Parameter value: The nested value.
    /// - Returns: Its type.
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

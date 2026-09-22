import Foundation

/// A decoded JSON value of unknown shape.
///
/// Used for endpoints whose payload has not been pinned down against a real
/// account. Decoding into this and then reading fields by name means one
/// unexpected field type cannot fail a whole response.
///
/// The accessors coerce between representations, because these services are
/// inconsistent about quoting numbers and booleans. Dictionaries of this type also
/// gain ``Swift/Dictionary/firstValue(_:)``, which matches keys loosely.
nonisolated enum JSONValue: Decodable, Sendable, Hashable {
    /// A JSON string.
    case string(String)
    /// A JSON number. Integers arrive here too.
    case number(Double)
    /// A JSON boolean.
    case bool(Bool)
    /// A JSON object.
    case object([String: JSONValue])
    /// A JSON array.
    case array([JSONValue])
    /// JSON `null`.
    case null

    /// Decodes whichever shape is present.
    ///
    /// Tried in order: null, boolean, number, string, array, object. Because booleans
    /// are tried before numbers, `true` decodes as ``bool(_:)`` rather than as `1`.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError.dataCorrupted` when the value matches none of the six
    ///   shapes.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognised JSON value")
        }
    }

    /// The object's members, or `nil` when this is not an object.
    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// The array's elements, or `nil` when this is not an array.
    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// The value as text, whatever it arrived as.
    ///
    /// A whole number renders without a decimal point. Objects, arrays and null return
    /// `nil`. The coercion matters because these services quote numbers in some rows
    /// and not in others.
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }

    /// The value as an integer.
    ///
    /// Numbers are truncated, strings are parsed, and a boolean becomes `1` or `0`.
    /// `nil` for anything else, or for a string that does not parse.
    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    /// The value as a double, parsing a string when necessary. `nil` for anything else.
    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    /// The value as a boolean.
    ///
    /// A number is true when non-zero. A string is matched case-insensitively against
    /// `true`, `1`, `s`, `si`, `sì`, `y`, `yes` and against `false`, `0`, `n`, `no`.
    /// `nil` for anything else.
    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value):
            switch value.lowercased() {
            case "true", "1", "s", "si", "sì", "y", "yes": return true
            case "false", "0", "n", "no": return false
            default: return nil
            }
        default: return nil
        }
    }
}

/// Reading fields out of a decoded object whose exact key spelling is not fixed.
nonisolated extension [String: JSONValue] {
    /// The first present, non-null value among several candidate keys.
    ///
    /// Exact matches are tried first, in the order given, then matches that ignore
    /// case, underscores and hyphens. These backends are not consistent between
    /// services — `data_esame` in one, `dataEsame` in another, `startdate` on Moodle —
    /// so matching loosely avoids a decoder that reads nothing because of one
    /// underscore.
    ///
    /// - Parameter keys: Candidate key spellings, most preferred first.
    /// - Returns: The first non-null value found, or `nil`.
    func firstValue(_ keys: [String]) -> JSONValue? {
        for key in keys {
            if let value = self[key], value != .null { return value }
        }
        let normalised = Dictionary(
            map { (JSONValue.normaliseKey($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        for key in keys {
            if let value = normalised[JSONValue.normaliseKey(key)], value != .null {
                return value
            }
        }
        return nil
    }
}

/// Key normalisation, shared with ``Swift/Dictionary/firstValue(_:)``.
nonisolated extension JSONValue {
    /// A key reduced to its comparable form: lowercased, without underscores or
    /// hyphens.
    ///
    /// - Parameter key: The key as written.
    /// - Returns: The normalised key.
    static func normaliseKey(_ key: String) -> String {
        key.lowercased().filter { $0 != "_" && $0 != "-" }
    }
}

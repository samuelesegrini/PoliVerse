import Foundation

/// A decoded JSON value of unknown shape.
///
/// Used for endpoints whose payload was never captured from a real account.
/// Decoding into this first, then reading fields by name, means an unexpected
/// field type cannot fail the whole response — which is exactly how the
/// libretto went out broken once, a single `typeMismatch` turning a working
/// list into an empty screen.
nonisolated enum JSONValue: Decodable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

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

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Text, whatever the value arrived as.
    ///
    /// Upstream is inconsistent about quoting numbers — the libretto sends
    /// `"cfu_conv_parz": 0` in one row and `"0"` in another — so a reader that
    /// insists on `String` loses real data.
    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

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

nonisolated extension [String: JSONValue] {
    /// The first present, non-null value among `keys`, matched case- and
    /// underscore-insensitively.
    ///
    /// The endpoint's own field names are unknown, and PoliMi's backends are
    /// not consistent between services — `data_esame` here, `dataEsame`
    /// there, `startdate` on Moodle. Matching loosely across a list of
    /// candidates costs nothing and avoids shipping a decoder that reads
    /// nothing because of a single underscore.
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

nonisolated extension JSONValue {
    static func normaliseKey(_ key: String) -> String {
        key.lowercased().filter { $0 != "_" && $0 != "-" }
    }
}

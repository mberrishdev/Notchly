import Foundation

/// A small, `Codable` stand-in for arbitrary JSON. Used for per-widget preferences and
/// for the key/value store handed to web widgets, both of which need to round-trip
/// values whose shape isn't known at compile time.
indirect enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
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
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    var doubleValue: Double? { if case .number(let value) = self { return value }; return nil }
    var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let value) = self { return value }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let value) = self { return value }; return nil }

    /// Bridges from the loosely typed values that arrive over the WebKit message bridge.
    init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            // NSNumber erases Bool, so ask CoreFoundation what it really is.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(any:)))
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues(JSONValue.init(any:)))
        default:
            self = .null
        }
    }

    /// Converts back to plain Foundation objects for the reply side of the bridge.
    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map(\.anyValue)
        case .object(let value): return value.mapValues(\.anyValue)
        }
    }
}

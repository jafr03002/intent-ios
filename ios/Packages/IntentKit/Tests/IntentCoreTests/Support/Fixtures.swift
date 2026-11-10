import Foundation
import Testing
@testable import IntentCore

/// A parsed JSON value, for reading the golden fixtures and comparing Swift output
/// against them structurally. Objects compare with null-valued keys dropped, so a
/// TS `null`, a TS `undefined` (absent) and a Swift `nil` (omitted) all agree.
enum JSON: Equatable, Codable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(_ key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    subscript(_ i: Int) -> JSON {
        if case .array(let a) = self, a.indices.contains(i) { return a[i] }
        return .null
    }

    var array: [JSON] { if case .array(let a) = self { a } else { [] } }
    var object: [String: JSON] { if case .object(let o) = self { o } else { [:] } }
    var string: String? { if case .string(let s) = self { s } else { nil } }
    var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    var isNull: Bool { self == .null }

    /// Numbers, plus the "NaN"/"Infinity"/"-Infinity" strings the generator writes
    /// for values JSON can't hold.
    var double: Double? {
        switch self {
        case .number(let n): n
        case .string("NaN"): .nan
        case .string("Infinity"): .infinity
        case .string("-Infinity"): -.infinity
        default: nil
        }
    }

    var int: Int? { double.flatMap { $0.isFinite ? Int($0) : nil } }

    /// Epoch ms -> Date (null -> nil).
    var date: Date? { double.map { Date(timeIntervalSince1970: $0 / 1000) } }

    var normalized: JSON {
        switch self {
        case .object(let o): .object(o.compactMapValues { $0 == .null ? nil : $0.normalized })
        case .array(let a): .array(a.map(\.normalized))
        default: self
        }
    }

    func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try Fixture.decoder.decode(T.self, from: Fixture.encoder.encode(self))
    }

    var description: String {
        guard let data = try? Fixture.encoder.encode(self) else { return "<json>" }
        return String(decoding: data, as: UTF8.self)
    }
}

enum Fixture {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    static func load(_ name: String) throws -> JSON {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
                               "missing fixture \(name).json - run ios/scripts/core-fixtures/generate.sh")
        return try decoder.decode(JSON.self, from: Data(contentsOf: url))
    }

    /// Any Encodable as JSON, for structural comparison with a fixture value.
    static func json<T: Encodable>(_ value: T) throws -> JSON {
        try decoder.decode(JSON.self, from: encoder.encode(value))
    }

    static func tz(_ json: JSON) throws -> TimeZone {
        let id = try #require(json.string)
        return try #require(TimeZone(identifier: id), "time zone \(id) unavailable")
    }
}

/// `#expect` that a Swift value encodes to the same JSON as the fixture's.
func expectJSON<T: Encodable>(_ actual: T, _ expected: JSON, _ context: @autoclosure () -> String = "",
                              sourceLocation: SourceLocation = #_sourceLocation) throws {
    let a = try Fixture.json(actual).normalized
    let e = expected.normalized
    #expect(a == e, "\(context())\n  swift: \(a)\n  ts:    \(e)", sourceLocation: sourceLocation)
}

/// Epoch ms of a Date, rounded to whole ms (what JS holds).
func ms(_ d: Date?) -> Double? { d.map { ($0.timeIntervalSince1970 * 1000).rounded() } }

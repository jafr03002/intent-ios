import Foundation
import IntentAPI
import IntentCore

// Plumbing for the Log feature: the localStorage stand-in, and the bridge between
// the generated API types and IntentCore's models. Everything here is
// Log-prefixed or fileprivate so it can't clash with another feature's helpers.

/// `localStorage` for the workout draft + active-session pointer. UserDefaults keeps
/// the values across launches, like the browser's storage does across reloads.
final class LogUserDefaultsStore: KeyValueStore, @unchecked Sendable {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func set(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
    func removeValue(forKey key: String) { defaults.removeObject(forKey: key) }
}

/// API <-> IntentCore conversion. Both sides are Codable with the spec's field
/// names, so a JSON round trip maps them 1:1 (the only `Date` field in the spec,
/// `WorkoutLogInput.startedAt`, travels as the server's ISO 8601 string).
enum LogAPI {
    private static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoWhole = Date.ISO8601FormatStyle()

    static func convert<In: Encodable, Out: Decodable>(_ value: In, to: Out.Type = Out.self) throws -> Out {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(iso.format(date))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let raw = try dec.singleValueContainer().decode(String.self)
            if let d = try? iso.parse(raw) { return d }
            return try isoWhole.parse(raw)
        }
        return try decoder.decode(Out.self, from: encoder.encode(value))
    }

    static func program(_ client: Client) async throws -> Program? {
        switch try await client.getCurrentProgram() {
        case .ok(let ok): return try convert(ok.body.json)
        case .notFound: return nil
        case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
        }
    }

    static func profile(_ client: Client) async throws -> LogProfile? {
        switch try await client.getProfile() {
        case .ok(let ok):
            let p = try ok.body.json
            return LogProfile(userId: p.userId, isIndependent: p.mode == "independent", weightUnit: p.weightUnit ?? "kg",
                              calibrationBriefingSeenAt: p.calibrationBriefingSeenAt)
        case .notFound: return nil
        case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
        }
    }

    static func history(_ client: Client) async throws -> [WorkoutLog] {
        try convert(try await client.listWorkouts(query: .init(limit: 200)).ok.body.json)
    }

    static func personalRecords(_ client: Client) async throws -> [PersonalRecord] {
        try convert(try await client.getPersonalRecords().ok.body.json)
    }

    static func saveWorkout(_ client: Client, _ input: WorkoutLogInput) async throws {
        let body: IntentSchemas.WorkoutLogInput = try convert(input)
        _ = try await client.createWorkout(body: .json(body)).created
    }
}

/// The profile fields the logger reads.
struct LogProfile: Sendable, Equatable {
    var userId: String
    var isIndependent: Bool
    var weightUnit: String
    var calibrationBriefingSeenAt: String?
}

/// Epoch ms, the web's `Date.now()`.
func logNowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

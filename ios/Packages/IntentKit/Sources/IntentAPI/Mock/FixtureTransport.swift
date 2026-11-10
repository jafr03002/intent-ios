import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A fake backend: answers every API operation from a bundled JSON fixture, so screens
/// render with realistic data on the CI simulator without sign-in or a live server.
/// Enabled by the `-IntentMock` launch argument (see the app's `AppServices`).
///
/// Fixture lookup, by the generated `operationID`:
///   Fixtures/<scenario>/<operationID>.json, falling back to Fixtures/default/<operationID>.json
/// File format: `{ "status": 200, "body": <any JSON> }` (`body` may be omitted, e.g. for 204).
/// Date tokens are replaced before decoding so data always lines up with "today":
///   {{date:N}}     yyyy-MM-dd, N days from today in the device time zone (N may be negative)
///   {{datetime:N}} ISO 8601 UTC timestamp, N days from now
///   {{weekday:N}}  weekday name ("monday"...) N days from today
///   {{dow:mon:W}}  yyyy-MM-dd of that weekday (mon..sun) in the Monday-start week W weeks
///                  from this one (W=0 this week, -1 last week); {{dowtime:mon:W}} = 17:30 local, ISO UTC
/// A missing fixture answers 404 `{"error":"no fixture for <op>"}` so gaps are obvious.
public struct FixtureTransport: ClientTransport {
    public let scenario: String
    public let now: @Sendable () -> Date
    public let latency: Duration
    public let timeZone: TimeZone

    public init(
        scenario: String = "default",
        latency: Duration = .milliseconds(120),
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scenario = scenario
        self.latency = latency
        self.timeZone = timeZone
        self.now = now
    }

    public func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        if latency > .zero { try? await Task.sleep(for: latency) }
        guard let raw = Self.loadFixture(operationID: operationID, scenario: scenario) else {
            return Self.json(status: 404, #"{"error":"no fixture for \#(operationID)"}"#)
        }
        let text = Self.expandTokens(raw, now: now(), timeZone: timeZone)
        guard let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? Int else {
            return Self.json(status: 500, #"{"error":"bad fixture for \#(operationID)"}"#)
        }
        guard let payload = object["body"] else {
            return (HTTPResponse(status: .init(code: status)), nil)
        }
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
        return Self.json(status: status, String(decoding: bodyData, as: UTF8.self))
    }

    // MARK: - Internals (internal for tests)

    static func loadFixture(operationID: String, scenario: String) -> String? {
        for folder in [scenario, "default"] {
            if let url = Bundle.module.url(
                forResource: operationID, withExtension: "json", subdirectory: "Fixtures/\(folder)"
            ), let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    static func expandTokens(_ text: String, now: Date, timeZone: TimeZone) -> String {
        guard text.contains("{{") else { return text }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let pattern = #"\{\{(date|datetime|weekday|dow|dowtime):(?:(mon|tue|wed|thu|fri|sat|sun):)?(-?\d+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let kind = ns.substring(with: match.range(at: 1))
            let weekdayName = match.range(at: 2).location == NSNotFound ? nil : ns.substring(with: match.range(at: 2))
            let offset = Int(ns.substring(with: match.range(at: 3))) ?? 0
            var day = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            if kind == "dow" || kind == "dowtime" {
                let order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                let todayIndex = (calendar.component(.weekday, from: now) + 5) % 7 // Monday = 0
                let target = order.firstIndex(of: weekdayName ?? "mon") ?? 0
                let start = calendar.startOfDay(for: now)
                day = calendar.date(byAdding: .day, value: target - todayIndex + offset * 7, to: start) ?? now
                if kind == "dowtime" {
                    day = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: day) ?? day
                }
            }
            switch kind {
            case "date", "dow":
                let c = calendar.dateComponents([.year, .month, .day], from: day)
                result += String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            case "datetime", "dowtime":
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                result += f.string(from: day)
            default:
                let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
                result += names[calendar.component(.weekday, from: day) - 1]
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func json(status: Int, _ text: String) -> (HTTPResponse, HTTPBody?) {
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json; charset=utf-8"
        return (response, HTTPBody(text))
    }
}

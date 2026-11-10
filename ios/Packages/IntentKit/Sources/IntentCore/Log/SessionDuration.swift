import Foundation

// Port of lib/sessionDuration.ts: formatting for the live clock and the calendar,
// plus the plausibility bands (which MUST stay in step with
// artifacts/api-server/src/lib/sessionDuration.ts, the source of truth).

public struct PlausibleBand: Sendable, Equatable, Codable {
    public var min: Int
    public var max: Int
}

public enum SessionDuration {
    public static let minSessionSeconds = 3 * 60
    public static let maxSessionSeconds = 4 * 60 * 60
    public static let minSecondsPerSet = 45
    public static let maxSecondsPerSet = 8 * 60
    /// Logged sessions of a day needed before its average is shown.
    public static let minSessionsForAverage = 3

    public static func plausibleBand(setCount: Int) -> PlausibleBand? {
        guard setCount > 0 else { return nil }
        let lo = Swift.max(minSessionSeconds, setCount * minSecondsPerSet)
        let hi = Swift.min(maxSessionSeconds, setCount * maxSecondsPerSet)
        return lo <= hi ? PlausibleBand(min: lo, max: hi) : nil
    }

    static func isPerformed(_ s: LoggedSet) -> Bool {
        s.weight > 0 || (s.reps ?? 0) > 0 || (s.repsLeft ?? 0) > 0 || (s.repsRight ?? 0) > 0
    }

    /// Mirrors the server's gate on whether a session counts toward the day's average.
    /// Checklist rows are exempt from the "every exercise has performed sets" rule.
    public static func countsTowardAverage(durationSeconds: Int?, exercisesLogged: [LoggedExercise]) -> Bool {
        let setCount = exercisesLogged.reduce(0) { $0 + $1.sets.count }
        guard let d = durationSeconds, let band = plausibleBand(setCount: setCount), d >= band.min, d <= band.max else {
            return false
        }
        let lifts = exercisesLogged.filter { $0.kind != .checklist }
        if lifts.isEmpty { return false }
        return lifts.allSatisfy { !$0.sets.isEmpty && $0.sets.allSatisfy(isPerformed) }
    }

    public static func countsTowardAverage(_ log: WorkoutLog) -> Bool {
        countsTowardAverage(durationSeconds: log.durationSeconds, exercisesLogged: log.exercisesLogged)
    }

    /// Ticking stopwatch: "18:42" under an hour, "1:07:15" at or past it.
    public static func formatClock(_ seconds: Double) -> String {
        // Non-finite input (JS would print "NaN:NaN") reads as 0 rather than trapping.
        let total = seconds.isFinite ? Int(Swift.max(0, seconds.rounded(.down))) : 0
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? "\(h):\(pad2(m)):\(pad2(s))" : "\(m):\(pad2(s))"
    }

    /// Settled duration for display after the fact: "1h 04m" / "48m".
    public static func formatSessionLength(_ seconds: Double) -> String {
        let total = seconds.isFinite ? Int(Swift.max(0, JS.round(seconds))) : 0
        let h = total / 3600
        let m = Int(JS.round(Double(total % 3600) / 60))
        if m == 60 { return "\(h + 1)h 00m" }
        return h > 0 ? "\(h)h \(pad2(m))m" : "\(m)m"
    }

    /// "18:12" - the session's local start time of day; "" when unreadable.
    public static func formatStartTime(_ startedAt: String, timeZone: TimeZone = .current) -> String {
        guard let p = JSDate.localParts(JSDate.parse(startedAt, timeZone), timeZone) else { return "" }
        return "\(pad2(p.hour)):\(pad2(p.minute))"
    }

    static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}

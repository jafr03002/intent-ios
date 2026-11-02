import Foundation

// Port of lib/greetingLines.ts: the dashboard greeting's second line, and the day
// its CTA starts.

/// Anything with a day number and label (a ProgramDay qualifies).
public protocol NamedDay {
    var dayNumber: Int { get }
    var label: String { get }
}

extension ProgramDay: NamedDay {}

public enum GreetingLines {
    static let sessionLines: [@Sendable (String) -> String] = [
        { "Ready for \($0)?" },
        { "\($0) is up next - let's make it count." },
        { "\($0) is waiting. Time to put in the work." },
        { "Nothing logs \($0) for you. Show up and get stronger." },
        { "\($0) today - go and beat last time." },
    ]

    static let genericLines = [
        "Ready to start your workout?",
        "Let's get moving.",
        "Time to put in the work.",
        "Your workout is waiting.",
        "Show up. Get stronger.",
    ]

    /// Day of the local year (Jan 1 = 1), as the web computes it: whole days of
    /// elapsed time since local midnight on Dec 31 - so across a DST change the hour
    /// after midnight still counts as the previous day.
    static func dayOfYear(_ at: Date, _ tz: TimeZone) -> Int {
        let t = JSDate.ms(at)
        guard let p = JSDate.localParts(t, tz) else { return 0 }
        let start = JSDate.local(Double(p.year), 0, 0, 0, 0, 0, 0, tz)
        return Int(((t - start) / JSDate.msPerDay).rounded(.down))
    }

    /// Rotates daily: a line naming the session, or a generic one with nothing to name.
    public static func greetingLine(dayLabel: String?, at: Date = Date(), timeZone: TimeZone = .current) -> String {
        let i = dayOfYear(at, timeZone)
        guard let dayLabel, !dayLabel.isEmpty else { return genericLines[mod(i, genericLines.count)] }
        return sessionLines[mod(i, sessionLines.count)](dayLabel)
    }

    private static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }

    /// The session the client is up to: the one after the last COMPLETED session,
    /// wrapping round; day one with nothing logged or an unknown last day.
    public static func nextSessionDay<T: NamedDay>(_ days: [T], lastCompletedDayNumber: Int?) -> T? {
        guard let first = days.first else { return nil }
        guard let last = lastCompletedDayNumber, let idx = days.firstIndex(where: { $0.dayNumber == last }) else { return first }
        return days[(idx + 1) % days.count]
    }
}

import Foundation

// Port of lib/programSchedule.ts: which program day falls on a date. Read-only:
// only the server writes schedules. Dates are local calendar strings (YYYY-MM-DD),
// parsed by hand - never through a UTC-midnight Date, which lands on the previous
// day west of Greenwich.

public struct UpcomingSlot: Sendable, Equatable, Codable {
    public var date: String
    public var dayId: Int?
}

public enum ProgramScheduleReader {
    public static let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// `^(\d{4})-(\d{2})-(\d{2})$` -> (y, m, d), or nil.
    static func ymd(_ date: String) -> (Double, Double, Double)? {
        let b = Array(date.utf8)
        guard b.count == 10, b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-") else { return nil }
        func num(_ r: Range<Int>) -> Double? {
            var v = 0
            for i in r {
                guard b[i] >= 48, b[i] <= 57 else { return nil }
                v = v * 10 + Int(b[i] - 48)
            }
            return Double(v)
        }
        guard let y = num(0..<4), let m = num(5..<7), let d = num(8..<10) else { return nil }
        return (y, m, d)
    }

    /// Monday-based weekday index (0 = Monday) of a YYYY-MM-DD string. Out-of-range
    /// parts roll over like JS's Date constructor ("2026-13-45" is 2027-02-14), and
    /// years 0000-0099 read as 1900-1999.
    public static func mondayIndexOf(_ date: String, timeZone: TimeZone = .current) -> Int? {
        guard let (y, m, d) = ymd(date) else { return nil }
        let t = JSDate.local(y, m - 1, d, 0, 0, 0, 0, timeZone)
        guard let p = JSDate.localParts(t, timeZone) else { return nil }
        return (p.weekday + 6) % 7
    }

    /// Whole calendar days from `from` to `to`; nil when either isn't YYYY-MM-DD.
    public static func daysBetween(_ from: String, _ to: String) -> Int? {
        guard let a = ymd(from), let b = ymd(to) else { return nil }
        let diff = JSDate.utcDate(b.0, b.1 - 1, b.2) - JSDate.utcDate(a.0, a.1 - 1, a.2)
        return Int(JS.round(diff / JSDate.msPerDay))
    }

    /// Local YYYY-MM-DD for `at` (the year is not zero-padded, as on the web).
    public static func todayDateString(at: Date = Date(), timeZone: TimeZone = .current) -> String {
        dateString(JSDate.ms(at), timeZone)
    }

    static func dateString(_ t: Double, _ tz: TimeZone) -> String {
        guard let p = JSDate.localParts(t, tz) else { return "NaN-NaN-NaN" }
        return "\(p.year)-\(SessionDuration.pad2(p.month0 + 1))-\(SessionDuration.pad2(p.day))"
    }

    /// Which dayNumber (if any) falls on `date`. A rotating cycle with no startDate
    /// reports nil rather than guessing an anchor.
    public static func resolveDayForDate(_ schedule: ProgramSchedule?, startDate: String?, date: String,
                                         timeZone: TimeZone = .current) -> Int? {
        guard let schedule, !schedule.slots.isEmpty else { return nil }
        switch schedule.mode {
        case .fixed:
            guard let index = mondayIndexOf(date, timeZone: timeZone), index < schedule.slots.count else { return nil }
            return schedule.slots[index]
        case .rotating:
            guard let startDate, !startDate.isEmpty, let elapsed = daysBetween(startDate, date), elapsed >= 0 else { return nil }
            return schedule.slots[elapsed % schedule.slots.count]
        }
    }

    /// The next `count` local days from `from` with their dayIds, for the program
    /// page's strip. A malformed `from` yields "NaN-NaN-NaN" dates, as on the web.
    public static func upcomingSlots(_ schedule: ProgramSchedule?, startDate: String?, from: String, count: Int,
                                     timeZone: TimeZone = .current) -> [UpcomingSlot] {
        guard let schedule, !schedule.slots.isEmpty else { return [] }
        let parts = from.split(separator: "-", omittingEmptySubsequences: false).map { JS.number(String($0)) }
        let y = parts.count > 0 ? parts[0] : .nan
        let m = parts.count > 1 ? parts[1] : .nan
        let d = parts.count > 2 ? parts[2] : .nan
        return (0..<max(0, count)).map { i in
            let at = JSDate.local(y, m - 1, d + Double(i), 0, 0, 0, 0, timeZone)
            let date = dateString(at, timeZone)
            return UpcomingSlot(date: date, dayId: resolveDayForDate(schedule, startDate: startDate, date: date, timeZone: timeZone))
        }
    }
}

import Foundation

/// The JavaScript `Date` operations the web logic relies on, done in plain
/// arithmetic over epoch milliseconds so the results are identical on Linux and
/// Darwin (no `Calendar`, whose Gregorian calendar turns Julian before 1582, and no
/// `DateFormatter`, whose output varies by OS and ICU version).
///
/// "Local" always means the `TimeZone` passed in - the web app's equivalent is the
/// browser's zone. Times are epoch ms as `Double`; `NaN` is JS's Invalid Date.
enum JSDate {
    static let msPerDay = 86_400_000.0

    // MARK: Civil calendar (proleptic Gregorian)

    /// Days since 1970-01-01 for a year / 1-based month / day (Howard Hinnant).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civilFromDays(_ z0: Int) -> (year: Int, month: Int, day: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// ECMAScript MakeDay + MakeTime as a UTC-less "wall clock" ms value. Month is
    /// 0-based and may overflow either way, like the JS constructor's.
    static func makeWallClock(year: Double, month0: Double, day: Double,
                              hour: Double = 0, minute: Double = 0, second: Double = 0, ms: Double = 0) -> Double {
        let parts = [year, month0, day, hour, minute, second, ms]
        guard parts.allSatisfy(\.isFinite) else { return .nan }
        let y = year.rounded(.towardZero), m = month0.rounded(.towardZero), dt = day.rounded(.towardZero)
        let ym = y + (m / 12).rounded(.down)
        let mn = m - (m / 12).rounded(.down) * 12
        guard Swift.abs(ym) < 400_000 else { return .nan }
        let days = Double(daysFromCivil(Int(ym), Int(mn) + 1, 1)) + dt - 1
        let time = hour.rounded(.towardZero) * 3_600_000 + minute.rounded(.towardZero) * 60_000
            + second.rounded(.towardZero) * 1000 + ms.rounded(.towardZero)
        return days * msPerDay + time
    }

    /// The constructor's two-digit-year rule: `new Date(26, 0, 1)` is 1926.
    static func constructorYear(_ y: Double) -> Double {
        let t = y.rounded(.towardZero)
        return (t >= 0 && t <= 99) ? 1900 + t : y
    }

    static func offsetMs(_ tz: TimeZone, atUTC t: Double) -> Double {
        Double(tz.secondsFromGMT(for: Date(timeIntervalSince1970: t / 1000))) * 1000
    }

    /// Wall clock in `tz` -> epoch ms, as V8 resolves it: an ambiguous wall time
    /// (DST ending) takes the offset from before the transition - the earlier
    /// instant - and a wall time inside a DST gap is read with the pre-gap offset,
    /// which moves it forward.
    static func utc(fromWallClock wall: Double, _ tz: TimeZone) -> Double {
        guard wall.isFinite else { return .nan }
        let before = offsetMs(tz, atUTC: wall - msPerDay)
        if offsetMs(tz, atUTC: wall - before) == before { return wall - before }
        let after = offsetMs(tz, atUTC: wall + msPerDay)
        if offsetMs(tz, atUTC: wall - after) == after { return wall - after }
        return wall - before
    }

    /// `new Date(y, m, d, h, mi, s, ms)` in `tz`.
    static func local(_ year: Double, _ month0: Double, _ day: Double,
                      _ hour: Double = 0, _ minute: Double = 0, _ second: Double = 0, _ ms: Double = 0,
                      _ tz: TimeZone) -> Double {
        utc(fromWallClock: makeWallClock(year: constructorYear(year), month0: month0, day: day,
                                         hour: hour, minute: minute, second: second, ms: ms), tz)
    }

    /// `Date.UTC(y, m, d)`.
    static func utcDate(_ year: Double, _ month0: Double, _ day: Double) -> Double {
        makeWallClock(year: constructorYear(year), month0: month0, day: day)
    }

    struct Parts: Equatable {
        var year: Int, month0: Int, day: Int, hour: Int, minute: Int, second: Int, ms: Int
        /// 0 = Sunday, like `getDay()`.
        var weekday: Int
    }

    /// `getFullYear()`/`getMonth()`/... in `tz`. Nil for an Invalid Date.
    static func localParts(_ t: Double, _ tz: TimeZone) -> Parts? {
        guard t.isFinite else { return nil }
        return utcParts(t + offsetMs(tz, atUTC: t))
    }

    static func utcParts(_ wall: Double) -> Parts? {
        guard wall.isFinite else { return nil }
        let days = (wall / msPerDay).rounded(.down)
        var rem = wall - days * msPerDay
        let (y, m, d) = civilFromDays(Int(days))
        let hour = Int(rem / 3_600_000); rem -= Double(hour) * 3_600_000
        let minute = Int(rem / 60000); rem -= Double(minute) * 60000
        let second = Int(rem / 1000); rem -= Double(second) * 1000
        let weekday = ((Int(days) % 7) + 7 + 4) % 7
        return Parts(year: y, month0: m - 1, day: d, hour: hour, minute: minute, second: second, ms: Int(rem), weekday: weekday)
    }

    /// `d.setDate(d.getDate() + n)` - same wall-clock time, n calendar days on.
    static func addDays(_ t: Double, _ n: Int, _ tz: TimeZone) -> Double {
        guard let p = localParts(t, tz) else { return .nan }
        let wall = makeWallClock(year: Double(p.year), month0: Double(p.month0), day: Double(p.day + n),
                                 hour: Double(p.hour), minute: Double(p.minute), second: Double(p.second), ms: Double(p.ms))
        return utc(fromWallClock: wall, tz)
    }

    /// `d.setHours(0, 0, 0, 0)`.
    static func localMidnight(_ t: Double, _ tz: TimeZone) -> Double {
        guard let p = localParts(t, tz) else { return .nan }
        return utc(fromWallClock: makeWallClock(year: Double(p.year), month0: Double(p.month0), day: Double(p.day)), tz)
    }

    // MARK: Parsing

    /// `new Date(string).getTime()` for the ISO-8601 shapes the API produces:
    /// `YYYY`, `YYYY-MM`, `YYYY-MM-DD` (read as UTC, as JS does) and date-times with
    /// `T` or a space, optional seconds/fraction and an optional `Z`/`±HH:MM`/`±HHMM`
    /// offset (read as local time without one). V8's legacy fallback parser accepts
    /// more ("Aug 12 2026", "2026-8-1"); those return NaN here.
    static func parse(_ raw: String, _ tz: TimeZone) -> Double {
        let s = Array(JS.trim(raw).utf8)
        var i = 0
        func digits(_ n: Int) -> Int? {
            guard i + n <= s.count else { return nil }
            var v = 0
            for k in i..<(i + n) {
                let c = s[k]
                guard c >= 48 && c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            i += n
            return v
        }
        func peek(_ c: UInt8) -> Bool { i < s.count && s[i] == c }

        var year: Int
        if peek(UInt8(ascii: "+")) || peek(UInt8(ascii: "-")) {
            let neg = s[i] == UInt8(ascii: "-")
            i += 1
            guard let y = digits(6) else { return .nan }
            year = neg ? -y : y
        } else {
            guard let y = digits(4) else { return .nan }
            year = y
        }
        var month = 1, day = 1
        if peek(UInt8(ascii: "-")) {
            i += 1
            guard let m = digits(2) else { return .nan }
            month = m
            if peek(UInt8(ascii: "-")) {
                i += 1
                guard let d = digits(2) else { return .nan }
                day = d
            }
        }
        guard month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth(year, month) else { return .nan }
        let dateWall = Double(daysFromCivil(year, month, day)) * msPerDay
        if i == s.count { return dateWall } // date-only: UTC

        guard s[i] == UInt8(ascii: "T") || s[i] == UInt8(ascii: "t") || s[i] == UInt8(ascii: " ") else { return .nan }
        i += 1
        guard let hh = digits(2), peek(UInt8(ascii: ":")) else { return .nan }
        i += 1
        guard let mi = digits(2) else { return .nan }
        var ss = 0, ms = 0
        if peek(UInt8(ascii: ":")) {
            i += 1
            guard let sec = digits(2) else { return .nan }
            ss = sec
            if peek(UInt8(ascii: ".")) || peek(UInt8(ascii: ",")) {
                i += 1
                var frac = "", count = 0
                while i < s.count, s[i] >= 48, s[i] <= 57 {
                    if count < 3 { frac.append(Character(Unicode.Scalar(s[i]))) }
                    count += 1
                    i += 1
                }
                guard count > 0 else { return .nan }
                while frac.count < 3 { frac += "0" }
                ms = Int(frac) ?? 0
            }
        }
        guard hh < 24 || (hh == 24 && mi == 0 && ss == 0 && ms == 0), mi < 60, ss < 60 else { return .nan }
        let wall = dateWall + Double(hh) * 3_600_000 + Double(mi) * 60000 + Double(ss) * 1000 + Double(ms)
        if i == s.count { return utc(fromWallClock: wall, tz) } // no offset: local
        if s[i] == UInt8(ascii: "Z") || s[i] == UInt8(ascii: "z") {
            i += 1
            return i == s.count ? wall : .nan
        }
        guard s[i] == UInt8(ascii: "+") || s[i] == UInt8(ascii: "-") else { return .nan }
        let sign: Double = s[i] == UInt8(ascii: "-") ? -1 : 1
        i += 1
        guard let oh = digits(2) else { return .nan }
        if peek(UInt8(ascii: ":")) { i += 1 }
        guard let om = digits(2), i == s.count else { return .nan }
        return wall - sign * (Double(oh) * 3_600_000 + Double(om) * 60000)
    }

    static func daysInMonth(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    // MARK: Date bridging

    static func ms(_ date: Date) -> Double { (date.timeIntervalSince1970 * 1000).rounded() }
    static func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }
}

import Foundation

// Port of lib/calibration.ts: dating the AI lineage's phases for the calendar,
// the calibration window and its review nudge, and the weekly check-in gate.
//
// Calibration is framed as one week; the calibration review (a readiness check,
// not a check-in) moves the client on, and the first check-in opens 7 days after
// it. Program rows carry no dates of their own and the API stamps every row with
// the CURRENT week, so each row's week is derived from `generatedAt` relative to
// the training start.
//
// "Local" is the injected `timeZone` (the web uses the browser's). Phases stay raw
// strings because the web paints whatever a row carries.

/// The fields of a Program row the phase maths reads.
public struct PhaseRow: Sendable, Equatable, Codable {
    public var shortTermPhase: String?
    public var weekInPhase: Int?
    public var generatedAt: String
    public var aiGenerated: Bool?
    public var startDate: String?

    public init(shortTermPhase: String?, weekInPhase: Int? = nil, generatedAt: String, aiGenerated: Bool? = true,
                startDate: String? = nil) {
        self.shortTermPhase = shortTermPhase; self.weekInPhase = weekInPhase; self.generatedAt = generatedAt
        self.aiGenerated = aiGenerated; self.startDate = startDate
    }

    public init(_ program: Program) {
        self.init(shortTermPhase: program.shortTermPhase?.rawValue, weekInPhase: program.weekInPhase,
                  generatedAt: program.generatedAt, aiGenerated: program.aiGenerated, startDate: program.startDate)
    }
}

public struct PhaseRange: Sendable, Equatable {
    public var phase: String
    /// Local midnight of the first day.
    public var start: Date
    /// Local midnight of the last day (inclusive).
    public var end: Date

    public var shortTermPhase: ShortTermPhase? { ShortTermPhase(rawValue: phase) }
}

public struct CalibrationGroup: Sendable, Equatable {
    public var start: Date
    public var end: Date
}

public enum CheckinGate: Sendable, Equatable {
    /// `firstAfterReview`: open, and nothing checked in since the review.
    case open(firstAfterReview: Bool)
    /// No check-ins during calibration: the review ends it.
    case closedForCalibration
    /// The first check-in opens a week after the review.
    case closedUntil(Date)

    public var isOpen: Bool { if case .open = self { true } else { false } }
}

public enum Calibration {
    public static let calibrationFamily: Set<String> = ["calibration", "calibration_review"]
    public static let firstCheckinAfterReviewDays = 7

    // MARK: Local dates

    /// `d.setDate(d.getDate() + days)`: same local time, `days` calendar days on.
    public static func addDays(_ date: Date, _ days: Int, timeZone: TimeZone = .current) -> Date {
        JSDate.date(JSDate.addDays(JSDate.ms(date), days, timeZone))
    }

    /// Local YYYY-MM-DD, matching how program.startDate is stored.
    public static func localDateString(_ date: Date, timeZone: TimeZone = .current) -> String {
        ProgramScheduleReader.dateString(JSDate.ms(date), timeZone)
    }

    /// Local midnight for a YYYY-MM-DD string (only the first 10 characters are
    /// read). Nil where the web gets an Invalid Date.
    public static func parseLocalDateString(_ dateStr: String, timeZone: TimeZone = .current) -> Date? {
        let t = parseLocalDateMs(dateStr, timeZone)
        return t.isFinite ? JSDate.date(t) : nil
    }

    static func parseLocalDateMs(_ dateStr: String, _ tz: TimeZone) -> Double {
        let head = String(String.UnicodeScalarView(dateStr.unicodeScalars.prefix(10)))
        let parts = head.split(separator: "-", omittingEmptySubsequences: false).map { JS.number(String($0)) }
        let y = parts.count > 0 ? parts[0] : .nan
        let m = parts.count > 1 ? parts[1] : .nan
        let d = parts.count > 2 ? parts[2] : .nan
        return JSDate.local(y, m - 1, d, 0, 0, 0, 0, tz)
    }

    // MARK: Phase ranges

    /// Day 1 of AI training: the newest AI row's startDate (as a local date), else
    /// local midnight of onboarding completion.
    public static func trainingStart(_ programs: [PhaseRow], onboardingCompletedAt: String?,
                                     timeZone: TimeZone = .current) -> Date? {
        let t = trainingStartMs(programs, onboardingCompletedAt, timeZone)
        return t.flatMap { $0.isFinite ? JSDate.date($0) : nil }
    }

    /// nil = JS null; NaN = an Invalid Date (which the web treats as present).
    static func trainingStartMs(_ programs: [PhaseRow], _ onboardingCompletedAt: String?, _ tz: TimeZone) -> Double? {
        let started = JS.stableSorted(programs.filter { ($0.aiGenerated ?? false) && !($0.startDate ?? "").isEmpty }) {
            Double(JS.localeCompare($1.generatedAt, $0.generatedAt))
        }.first
        if let started { return parseLocalDateMs(started.startDate!, tz) }
        guard let onboarding = onboardingCompletedAt, !onboarding.isEmpty else { return nil }
        return JSDate.localMidnight(JSDate.parse(onboarding, tz), tz)
    }

    /// The AI lineage's phases as local-date ranges, newest row running through
    /// `today`. Fresh starts into calibration cover the week they were written in;
    /// later rows start the week after the previous one (or later). Adjacent weeks
    /// sharing a phase merge.
    public static func buildPhaseRanges(_ programs: [PhaseRow], onboardingCompletedAt: String?, today: Date = Date(),
                                        timeZone tz: TimeZone = .current) -> [PhaseRange] {
        guard let base = trainingStartMs(programs, onboardingCompletedAt, tz), base.isFinite else { return [] }
        // nil = NaN week (an unparseable generatedAt), which JS carries through Math.max.
        func weekIndexAt(_ t: Double) -> Int? {
            let days = JS.round((JSDate.localMidnight(t, tz) - base) / JSDate.msPerDay)
            guard days.isFinite else { return nil }
            return max(0, Int((days / 7).rounded(.down)))
        }

        let rows = JS.stableSorted(programs.filter { ($0.aiGenerated ?? false) && !($0.shortTermPhase ?? "").isEmpty }) {
            Double(JS.localeCompare($0.generatedAt, $1.generatedAt))
        }

        var phaseByWeek: [Int: String] = [:]
        var prevWeek: Int?? = .some(-1) // .some(nil) = NaN
        for p in rows {
            let written = weekIndexAt(JSDate.parse(p.generatedAt, tz))
            let freshStart = p.shortTermPhase == "calibration" && (p.weekInPhase ?? 1) <= 1
            let prev = prevWeek!
            let week: Int?
            if freshStart || (prev.map { $0 < 0 } ?? false) {
                week = written
            } else if let w = written, let pw = prev {
                week = max(w, pw + 1)
            } else {
                week = nil
            }
            if let week {
                phaseByWeek[week] = p.shortTermPhase!
                for w in phaseByWeek.keys where w > week { phaseByWeek[w] = nil }
            }
            prevWeek = .some(week)
        }

        guard let lastPrev = prevWeek!, let todayWeek = weekIndexAt(JSDate.ms(today)) else { return [] }
        let lastWeek = max(lastPrev, todayWeek)

        var weeks: [(phase: String, start: Double, end: Double)] = []
        var phase: String?
        if lastWeek >= 0 {
            for w in 0...lastWeek {
                phase = phaseByWeek[w] ?? phase
                guard let phase else { continue }
                let start = JSDate.addDays(base, w * 7, tz)
                weeks.append((phase, start, JSDate.addDays(start, 6, tz)))
            }
        }

        var ranges: [(phase: String, start: Double, end: Double)] = []
        for w in weeks {
            if let last = ranges.last, last.phase == w.phase, JSDate.addDays(last.end, 1, tz) == w.start {
                ranges[ranges.count - 1].end = w.end
            } else {
                ranges.append(w)
            }
        }
        return ranges.map { PhaseRange(phase: $0.phase, start: JSDate.date($0.start), end: JSDate.date($0.end)) }
    }

    public static func findPhaseRange(_ ranges: [PhaseRange], _ date: Date) -> PhaseRange? {
        let t = JSDate.ms(date)
        return ranges.first { t >= JSDate.ms($0.start) && t <= JSDate.ms($0.end) }
    }

    // MARK: Check-in gate

    /// When a weekly check-in is allowed (mirrors api-server's lib/checkinGate.ts).
    public static func checkinGate(_ programs: [PhaseRow], latestCheckinAt: String?, now: Date = Date(),
                                   timeZone tz: TimeZone = .current) -> CheckinGate {
        let newestFirst = JS.stableSorted(programs.filter { $0.aiGenerated ?? false }) {
            Double(JS.localeCompare($1.generatedAt, $0.generatedAt))
        }
        guard let newest = newestFirst.first else { return .open(firstAfterReview: false) }
        if newest.shortTermPhase == "calibration" { return .closedForCalibration }

        var reviewAt: Double?
        var sawCalibration = false
        for p in newestFirst {
            if p.shortTermPhase == "calibration" {
                sawCalibration = true
                break
            }
            reviewAt = JSDate.parse(p.generatedAt, tz)
        }
        guard sawCalibration, let reviewAt else { return .open(firstAfterReview: false) }
        if let latest = latestCheckinAt, !latest.isEmpty, JSDate.parse(latest, tz) >= reviewAt {
            return .open(firstAfterReview: false)
        }
        let opensAt = reviewAt + Double(firstCheckinAfterReviewDays) * JSDate.msPerDay
        // An unparseable review time (NaN) leaves the gate closed with an invalid
        // date, as on the web.
        return JSDate.ms(now) >= opensAt ? .open(firstAfterReview: true) : .closedUntil(JSDate.date(opensAt))
    }

    // MARK: Calibration window

    public static func buildCalibrationGroups(_ ranges: [PhaseRange], timeZone tz: TimeZone = .current) -> [CalibrationGroup] {
        let family = JS.stableSorted(ranges.filter { calibrationFamily.contains($0.phase) }) {
            JSDate.ms($0.start) - JSDate.ms($1.start)
        }
        var groups: [CalibrationGroup] = []
        for r in family {
            if let last = groups.last, JSDate.addDays(JSDate.ms(last.end), 1, tz) == JSDate.ms(r.start) {
                groups[groups.count - 1].end = r.end
            } else {
                groups.append(CalibrationGroup(start: r.start, end: r.end))
            }
        }
        return groups
    }

    public static func findCalibrationGroup(_ groups: [CalibrationGroup], _ date: Date) -> CalibrationGroup? {
        let t = JSDate.ms(date)
        return groups.first { t >= JSDate.ms($0.start) && t <= JSDate.ms($0.end) }
    }

    /// "Review possible" from day 8 of the group (7 full days in) through its end.
    public static func isReviewPossible(_ group: CalibrationGroup, _ date: Date, timeZone tz: TimeZone = .current) -> Bool {
        let t = JSDate.ms(date), s = JSDate.ms(group.start), e = JSDate.ms(group.end)
        return t >= s && t <= e && t >= JSDate.addDays(s, 7, tz)
    }

    /// Show the calibration walkthrough once, the first time `today` falls in an
    /// active calibration window.
    ///
    /// NOTE (ported faithfully): the web builds the phase ranges here against the
    /// real clock, not `today` (it calls buildPhaseRanges without its `today`
    /// argument), so pass the real time as `now`.
    public static func shouldShowCalibrationWalkthrough(_ programs: [PhaseRow], onboardingCompletedAt: String?,
                                                        calibrationWalkthroughSeenAt: String?, today: Date,
                                                        now: Date = Date(), timeZone tz: TimeZone = .current) -> Bool {
        if let seen = calibrationWalkthroughSeenAt, !seen.isEmpty { return false }
        let ranges = buildPhaseRanges(programs, onboardingCompletedAt: onboardingCompletedAt, today: now, timeZone: tz)
        return findCalibrationGroup(buildCalibrationGroups(ranges, timeZone: tz), today) != nil
    }

    // MARK: Program predicates

    /// A session against this program is a calibration session (ticks, no numbers,
    /// a briefing first).
    public static func isCalibrationProgram(aiGenerated: Bool?, shortTermPhase: String?) -> Bool {
        (aiGenerated ?? false) && shortTermPhase == "calibration"
    }

    public static func isCalibrationProgram(_ program: Program?) -> Bool {
        guard let program else { return false }
        return isCalibrationProgram(aiGenerated: program.aiGenerated, shortTermPhase: program.shortTermPhase?.rawValue)
    }

    /// Where a Start press goes during calibration.
    public static func calibrationBriefingHref(dayNumber: Int) -> String {
        "/calibration/briefing?day=\(dayNumber)"
    }

    /// An AI program committed to a start date still in the future. Manual programs
    /// are never locked.
    public static func isPreCalibrationLocked(aiGenerated: Bool?, startDate: String?, today: Date,
                                              timeZone tz: TimeZone = .current) -> Bool {
        guard aiGenerated ?? false, let startDate, !startDate.isEmpty else { return false }
        let head = String(String.UnicodeScalarView(startDate.unicodeScalars.prefix(10)))
        return jsStringGreater(head, localDateString(today, timeZone: tz))
    }

    public static func isPreCalibrationLocked(_ program: Program?, today: Date, timeZone tz: TimeZone = .current) -> Bool {
        guard let program else { return false }
        return isPreCalibrationLocked(aiGenerated: program.aiGenerated, startDate: program.startDate, today: today, timeZone: tz)
    }

    /// JS `a > b` on strings: UTF-16 code-unit order.
    static func jsStringGreater(_ a: String, _ b: String) -> Bool {
        let ua = Array(a.utf16), ub = Array(b.utf16)
        for (x, y) in zip(ua, ub) where x != y { return x > y }
        return ua.count > ub.count
    }
}

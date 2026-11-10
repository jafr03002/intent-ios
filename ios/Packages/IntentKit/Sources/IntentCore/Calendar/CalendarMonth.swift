import Foundation

// Port of the pure parts of pages/calendar.tsx and components/calendar/MonthGrid.tsx:
// laying out a month (Monday-first), which phase each day wears (calibration
// suppression included), the phase bands per week row, and the session sheet's
// text helpers. The views live in the app's Features/Calendar.
//
// "Local" is the injected `timeZone` (the web uses the browser's).

public enum CalendarMonth {
    /// An independent user's phase has no end date - it runs until they change it
    /// (`new Date(9999, 0, 1)`).
    public static func openEnd(timeZone tz: TimeZone = .current) -> Date {
        JSDate.date(JSDate.local(9999, 0, 1, 0, 0, 0, 0, tz))
    }

    /// One cell of the month grid (`MonthDay`).
    public struct Day: Sendable, Equatable {
        /// YYYY-MM-DD.
        public var date: String
        public var day: Int
        public var isToday: Bool
        public var isPast: Bool
        public var trained: Bool
        public var planned: Bool
        /// The phase painted on this day (already calibration-suppressed), if any.
        public var phase: String?
        /// First day of its phase run - the band's end goes fully round here.
        public var phaseStart: Bool
        /// Where the band carries the phase's name: its start, or the 1st of the month inside a run.
        public var phaseNamed: Bool
        /// Last day of its phase run.
        public var phaseEnd: Bool
        public var accessibilityLabel: String
    }

    /// One rounded band per run of same-phase days in a week row.
    public struct BandRun: Sendable, Equatable {
        /// Column range, 0...6.
        public var from: Int
        public var to: Int
        public var phase: String
        public var start: Bool
        public var end: Bool
        public var named: Bool
    }

    public static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]
    static let enGBMonths = ["January", "February", "March", "April", "May", "June", "July", "August",
                             "September", "October", "November", "December"]
    static let enGBWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    // MARK: Month layout

    public static func dateKey(year: Int, month0: Int, day: Int) -> String {
        "\(year)-\(SessionDuration.pad2(month0 + 1))-\(SessionDuration.pad2(day))"
    }

    /// Year and 0-based month of `date` in `tz`.
    public static func yearMonth(of date: Date, timeZone tz: TimeZone = .current) -> (year: Int, month0: Int) {
        guard let p = JSDate.localParts(JSDate.ms(date), tz) else { return (1970, 0) }
        return (p.year, p.month0)
    }

    /// The month `delta` months from (year, month0), as `new Date(y, m + delta, 1)`.
    public static func shiftMonth(year: Int, month0: Int, by delta: Int) -> (year: Int, month0: Int) {
        let total = year * 12 + month0 + delta
        let y = Int((Double(total) / 12).rounded(.down))
        return (y, total - y * 12)
    }

    public static func daysInMonth(year: Int, month0: Int) -> Int {
        JSDate.daysInMonth(year, month0 + 1)
    }

    /// Leading blank cells before the 1st (Monday-first): `(firstDay.getDay() + 6) % 7`.
    public static func startPadding(year: Int, month0: Int, timeZone tz: TimeZone = .current) -> Int {
        guard let p = JSDate.localParts(JSDate.local(Double(year), Double(month0), 1, 0, 0, 0, 0, tz), tz) else { return 0 }
        return (p.weekday + 6) % 7
    }

    /// "November 2026" (`toLocaleDateString("en-GB", { month: "long", year: "numeric" })`).
    public static func monthTitle(year: Int, month0: Int) -> String {
        "\(enGBMonths[month0]) \(year)"
    }

    public static func monthName(_ month0: Int) -> String { enGBMonths[month0] }

    /// Local midnight of a grid day.
    public static func cellDate(year: Int, month0: Int, day: Int, timeZone tz: TimeZone = .current) -> Date {
        JSDate.date(JSDate.local(Double(year), Double(month0), Double(day), 0, 0, 0, 0, tz))
    }

    // MARK: Phases

    /// The phase ranges the calendar paints. AI mode paints its program lineage;
    /// Independent mode only has the phase set now, painted from today on, open-ended.
    public static func phaseRanges(isIndependent: Bool, goal: String?, programs: [PhaseRow],
                                   onboardingCompletedAt: String?, now: Date, timeZone tz: TimeZone = .current) -> [PhaseRange] {
        if isIndependent {
            let todayMidnight = JSDate.date(JSDate.localMidnight(JSDate.ms(now), tz))
            return [PhaseRange(phase: IndependentTargets.goalToPhase(goal).shortTermPhase.rawValue,
                               start: todayMidnight, end: openEnd(timeZone: tz))]
        }
        return Calibration.buildPhaseRanges(programs, onboardingCompletedAt: onboardingCompletedAt, today: now, timeZone: tz)
    }

    /// The phase shown on `date`. While today is still inside a calibration run every
    /// other phase is hidden - they're provisional until the review happens.
    public static func visiblePhase(on date: Date, ranges: [PhaseRange], activeCalibrationGroup: CalibrationGroup?) -> PhaseRange? {
        guard let raw = Calibration.findPhaseRange(ranges, date) else { return nil }
        if activeCalibrationGroup != nil && !Calibration.calibrationFamily.contains(raw.phase) { return nil }
        return raw
    }

    /// "Week 2" of the phase `on` falls in; nil for an open-ended phase and for calibration
    /// (presented as one week).
    public static func phaseWeek(_ range: PhaseRange, on: Date, timeZone tz: TimeZone = .current) -> Int? {
        if JSDate.ms(range.end) >= JSDate.ms(openEnd(timeZone: tz)) || Calibration.calibrationFamily.contains(range.phase) {
            return nil
        }
        return Int(((JSDate.ms(on) - JSDate.ms(range.start)) / (7 * JSDate.msPerDay)).rounded(.down)) + 1
    }

    // MARK: Days

    /// Builds the month's cells.
    /// - Parameters:
    ///   - sessionsByDate: logged session labels per YYYY-MM-DD (nil label = "Workout").
    ///   - plannedLabelOn: the fixed-schedule day label for a date, if any.
    public static func buildDays(year: Int, month0: Int, todayString: String, sessionsByDate: [String: [String?]],
                                 ranges: [PhaseRange], activeCalibrationGroup: CalibrationGroup?,
                                 plannedLabelOn: (String) -> String?, timeZone tz: TimeZone = .current) -> [Day] {
        let count = daysInMonth(year: year, month0: month0)
        let monthOnly = monthName(month0)
        return (1...count).map { day in
            let date = dateKey(year: year, month0: month0, day: day)
            let cell = cellDate(year: year, month0: month0, day: day, timeZone: tz)
            let sessions = sessionsByDate[date] ?? []
            let range = visiblePhase(on: cell, ranges: ranges, activeCalibrationGroup: activeCalibrationGroup)
            let isPast = Calibration.jsStringGreater(todayString, date)
            let planned = sessions.isEmpty && !isPast ? plannedLabelOn(date) : nil
            let phaseStart = range.map { JSDate.ms($0.start) == JSDate.ms(cell) } ?? false
            let phaseEnd = range.map { JSDate.ms($0.end) == JSDate.ms(cell) } ?? false
            let what: String
            if !sessions.isEmpty {
                what = "\(sessions.count) session\(sessions.count == 1 ? "" : "s"): " + sessions.map { $0 ?? "Workout" }.joined(separator: ", ")
            } else if let planned {
                what = "planned: \(planned)"
            } else {
                what = isPast ? "rest day" : "nothing planned"
            }
            let phasePart = range.map { ", \(PhaseColors.label($0.phase)) phase" } ?? ""
            return Day(date: date, day: day, isToday: date == todayString, isPast: isPast, trained: !sessions.isEmpty,
                       planned: planned != nil, phase: range?.phase, phaseStart: phaseStart,
                       phaseNamed: range != nil && (phaseStart || day == 1), phaseEnd: phaseEnd,
                       accessibilityLabel: "\(day) \(monthOnly)\(phasePart) - \(what)")
        }
    }

    /// The grid as week rows of 7 (nil = padding).
    public static func rows(padding: Int, days: [Day]) -> [[Day?]] {
        let rowCount = (padding + days.count + 6) / 7
        return (0..<rowCount).map { r in
            (0..<7).map { c in
                let i = r * 7 + c - padding
                return days.indices.contains(i) ? days[i] : nil
            }
        }
    }

    /// `PhaseBands`: one run per stretch of same-phase days in a week row. A run breaks
    /// where a new phase starts even if the phase name repeats.
    public static func bandRuns(_ cells: [Day?]) -> [BandRun] {
        var runs: [BandRun] = []
        for (c, cell) in cells.enumerated() {
            guard let d = cell, let phase = d.phase else { continue }
            if var last = runs.last, last.to == c - 1, last.phase == phase, !d.phaseStart {
                last.to = c
                last.end = d.phaseEnd
                last.named = last.named || d.phaseNamed
                runs[runs.count - 1] = last
            } else {
                runs.append(BandRun(from: c, to: c, phase: phase, start: d.phaseStart, end: d.phaseEnd, named: d.phaseNamed))
            }
        }
        return runs
    }

    // MARK: Session sheet

    /// "Monday 26 October 2026": `new Date(session.date).toLocaleDateString("en-GB",
    /// { weekday: "long", day: "numeric", month: "long", year: "numeric" })`.
    /// NOTE (ported faithfully): a bare YYYY-MM-DD parses as UTC midnight, so west of
    /// Greenwich this shows the previous day.
    public static func longDate(_ date: String, timeZone tz: TimeZone = .current) -> String {
        guard let p = JSDate.localParts(JSDate.parse(date, tz), tz) else { return "Invalid Date" }
        return "\(enGBWeekdays[p.weekday]) \(p.day) \(enGBMonths[p.month0]) \(p.year)"
    }

    /// "Calibration review possible from 9 November." date part (`{ day: "numeric", month: "long" }`).
    public static func dayMonth(_ date: Date, timeZone tz: TimeZone = .current) -> String {
        guard let p = JSDate.localParts(JSDate.ms(date), tz) else { return "Invalid Date" }
        return "\(p.day) \(enGBMonths[p.month0])"
    }

    public static func modeLabel(_ log: WorkoutLog) -> String {
        log.loggingMode == .calibration ? "Calibration" : log.mode == .independent ? "Independent mode" : "AI mode"
    }

    public static func exerciseHasData(_ ex: LoggedExercise) -> Bool {
        ex.sets.contains { !SessionLogs.isEmptySet($0) }
    }

    public static func isUnilateralSet(_ s: LoggedSet) -> Bool {
        s.repsLeft != nil || s.repsRight != nil
    }

    /// Comparable rep count: the lower side for unilateral sets.
    public static func setReps(_ s: LoggedSet) -> Int {
        isUnilateralSet(s) ? min(s.repsLeft ?? 0, s.repsRight ?? 0) : (s.reps ?? 0)
    }

    /// "8" or "8L / 7R".
    public static func setRepsLabel(_ s: LoggedSet) -> String {
        isUnilateralSet(s) ? "\(s.repsLeft ?? 0)L / \(s.repsRight ?? 0)R" : "\(s.reps ?? 0)"
    }

    /// "80kg × 8".
    public static func setLabel(_ s: LoggedSet) -> String {
        "\(JS.string(s.weight))kg × \(setRepsLabel(s))"
    }

    /// Per-set progression delta: "+5kg" / "-2 reps" / "–" (unchanged).
    public static func deltaText(_ d: Double, unit: String) -> String {
        if d == 0 { return "–" }
        return "\(d > 0 ? "+" : "")\(JS.string(JS.round(d * 100) / 100))\(unit)"
    }

    /// The row under a multi-session day: "6 exercises · 16 sets · 1h 02m".
    public static func sessionSummary(_ session: WorkoutLog) -> String {
        if session.loggingMode == .calibration {
            let lifts = session.exercisesLogged.filter { $0.kind != .checklist }
            let ticked = lifts.reduce(0) { $0 + $1.sets.filter(\.completed).count }
            var parts = ["Calibration", "\(lifts.count) exercise\(lifts.count == 1 ? "" : "s")",
                         "\(ticked) set\(ticked == 1 ? "" : "s") done"]
            if let d = session.durationSeconds { parts.append(SessionDuration.formatSessionLength(Double(d))) }
            return parts.joined(separator: " · ")
        }
        let exercises = session.exercisesLogged.filter(exerciseHasData)
        let sets = exercises.reduce(0) { $0 + $1.sets.filter { !SessionLogs.isEmptySet($0) }.count }
        var parts = ["\(exercises.count) exercise\(exercises.count == 1 ? "" : "s")"]
        if sets > 0 { parts.append("\(sets) set\(sets == 1 ? "" : "s")") }
        if let d = session.durationSeconds { parts.append(SessionDuration.formatSessionLength(Double(d))) }
        return parts.joined(separator: " · ")
    }

    /// The most recent session strictly before `session` (by date, then id) with real
    /// data for `name` - its sets, or nil (skips empty/abandoned sessions).
    public static func previousSets(for name: String, before session: WorkoutLog, in all: [WorkoutLog]) -> [LoggedSet]? {
        let priors = JS.stableSorted(all.filter { w in
            w.id != session.id && (w.date < session.date || (w.date == session.date && w.id < session.id))
        }) { a, b in
            a.date == b.date ? Double(b.id - a.id) : Double(JS.localeCompare(b.date, a.date))
        }
        for w in priors {
            if let ex = w.exercisesLogged.first(where: { $0.name == name }), exerciseHasData(ex) { return ex.sets }
        }
        return nil
    }

    /// One set row's deltas against the previous session's same-numbered set; nil when
    /// there is nothing to compare with.
    public static func setDelta(_ s: LoggedSet, previous: [LoggedSet]?) -> (weight: Double, reps: Int)? {
        guard let prev = previous?.first(where: { $0.setNumber == s.setNumber }), !SessionLogs.isEmptySet(prev) else { return nil }
        return (s.weight - prev.weight, setReps(s) - setReps(prev))
    }
}

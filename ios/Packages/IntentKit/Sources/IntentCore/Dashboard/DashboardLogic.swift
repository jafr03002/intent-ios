import Foundation

// The pure parts of pages/dashboard.tsx and components/dashboard/WeekStrip.tsx:
// the greeting, the week strip's days, the weekly check-in banner gate and the
// "PRs this week" count. View state stays in the app's Dashboard feature.

/// One planned program day, as the week strip needs it.
public struct DashboardPlannedDay: Sendable, Equatable, NamedDay {
    public var dayNumber: Int
    public var label: String
    public init(dayNumber: Int, label: String) { self.dayNumber = dayNumber; self.label = label }
}

/// One logged session, as the week strip needs it.
public struct DashboardLoggedSession: Sendable, Equatable {
    public var id: Int
    public var date: String
    public var dayLabel: String?
    public init(id: Int, date: String, dayLabel: String?) { self.id = id; self.date = date; self.dayLabel = dayLabel }
}

/// A day of the dashboard's week arc.
public struct WeekStripDay: Sendable, Equatable {
    /// Local YYYY-MM-DD.
    public var date: String
    /// "Mon".."Sun".
    public var weekday: String
    public var dayOfMonth: Int
    public var isToday: Bool
    /// Sessions logged on this date, in the order the API listed them (newest first).
    public var logged: [DashboardLoggedSession]
    /// What a fixed schedule pencils in for the date (nil for rotating programs).
    public var planned: DashboardPlannedDay?
    /// The logged session's label, else the planned one.
    public var label: String?
    public var done: Bool { !logged.isEmpty }
}

public enum DashboardLogic {
    // MARK: Dates

    /// `greet()`: by the local hour.
    public static func greeting(hour: Int) -> String {
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    public static func greeting(at now: Date = Date(), timeZone: TimeZone = .current) -> String {
        greeting(hour: JSDate.localParts(JSDate.ms(now), timeZone)?.hour ?? 0)
    }

    /// `todayDateString()`: local YYYY-MM-DD.
    public static func todayDateString(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        ProgramScheduleReader.todayDateString(at: now, timeZone: timeZone)
    }

    /// `startOfWeekDateString()`: Monday of the current local week.
    public static func startOfWeekDateString(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let t = JSDate.ms(now)
        let day = JSDate.localParts(t, timeZone)?.weekday ?? 1 // 0 = Sunday
        let diffToMonday = day == 0 ? -6 : 1 - day
        return ProgramScheduleReader.dateString(JSDate.addDays(t, diffToMonday, timeZone), timeZone)
    }

    /// `daysSince(dateStr)`: whole days since `new Date(dateStr)`, floored; infinity
    /// for a missing date.
    ///
    /// NOTE (ported faithfully): `new Date("YYYY-MM-DD")` is UTC midnight, not local,
    /// so a date-only string reads up to a day off east/west of Greenwich.
    public static func daysSince(_ dateStr: String?, now: Date = Date(), timeZone: TimeZone = .current) -> Double {
        guard let dateStr, !dateStr.isEmpty else { return .infinity }
        let then = JSDate.parse(dateStr, timeZone)
        return ((JSDate.ms(now) - then) / JSDate.msPerDay).rounded(.down)
    }

    // MARK: Hero + banner

    /// "PRs this week": personal records dated within the last 7 days.
    public static func recentPrCount(_ prDates: [String], now: Date = Date(), timeZone: TimeZone = .current) -> Int {
        prDates.filter { daysSince($0, now: now, timeZone: timeZone) <= 7 }.count
    }

    /// `showCheckinBanner` once every query has settled: AI mode only, an AI program
    /// must exist, never during calibration, the first one a week after the review,
    /// then every 7 days.
    public static func showCheckinBanner(isIndependent: Bool, hasProgram: Bool, programs: [PhaseRow],
                                         latestCheckinSubmittedAt: String?, onboardingCompletedAt: String?,
                                         now: Date = Date(), timeZone: TimeZone = .current) -> Bool {
        if isIndependent { return false }
        if !hasProgram { return false }
        let gate = Calibration.checkinGate(programs, latestCheckinAt: latestCheckinSubmittedAt, now: now, timeZone: timeZone)
        guard case .open(let firstAfterReview) = gate else { return false }
        if firstAfterReview { return true }
        guard let latest = latestCheckinSubmittedAt else {
            // A program from before calibration existed: the original day-6 nudge.
            guard let start = Calibration.trainingStart(programs, onboardingCompletedAt: onboardingCompletedAt,
                                                        timeZone: timeZone) else { return false }
            return ((JSDate.ms(now) - JSDate.ms(start)) / JSDate.msPerDay).rounded(.down) >= 6
        }
        return daysSince(latest, now: now, timeZone: timeZone) >= 7
    }

    /// The "to go" figure under the progress card.
    public static func toGo(trendWeight: Double, goalWeight: Double?) -> Double? {
        goalWeight.map { abs(trendWeight - $0) }
    }

    /// "N/4 logged" on today's check-in.
    public static func loggedCount(weight: Double?, calories: Int?, steps: Int?, cardioType: String?) -> Int {
        [weight != nil, calories != nil, steps != nil, cardioType != nil].filter { $0 }.count
    }

    // MARK: Week strip

    /// The arc's geometry (WeekStrip.tsx): every circle's centre sits on one parabola.
    public enum Arc {
        public static let height: Double = 118
        public static let top: Double = 38
        public static let sink: Double = 1.6
        public static let todaySize: Double = 48
        public static let todayLift: Double = 8
        public static let daySize: Double = 38

        public static func y(offset: Int) -> Double { top + sink * Double(offset * offset) }
        public static func opacity(offset: Int) -> Double { 1 - 0.06 * Double(abs(offset)) }
    }

    /// Seven days from `weekStart` (a Monday). Only a fixed schedule says what a day
    /// holds; a logged session shows either way.
    public static func weekStripDays(weekStart: String, today: String, schedule: ProgramSchedule?,
                                     programStartDate: String?, days: [DashboardPlannedDay],
                                     sessions: [DashboardLoggedSession],
                                     timeZone: TimeZone = .current) -> [WeekStripDay] {
        var byDate: [String: [DashboardLoggedSession]] = [:]
        for s in sessions { byDate[s.date, default: []].append(s) }
        let isFixed = schedule?.mode == .fixed
        let start = Calibration.parseLocalDateString(weekStart, timeZone: timeZone)
        return (0..<7).map { i in
            let dateValue = start.map { Calibration.addDays($0, i, timeZone: timeZone) }
            let date = dateValue.map { ProgramScheduleReader.todayDateString(at: $0, timeZone: timeZone) } ?? "NaN-NaN-NaN"
            let logged = byDate[date] ?? []
            let plannedNumber = isFixed
                ? ProgramScheduleReader.resolveDayForDate(schedule, startDate: programStartDate, date: date, timeZone: timeZone)
                : nil
            let planned = plannedNumber.flatMap { n in days.first { $0.dayNumber == n } }
            let dom = dateValue.flatMap { JSDate.localParts(JSDate.ms($0), timeZone)?.day } ?? 0
            return WeekStripDay(
                date: date,
                weekday: ProgramScheduleReader.weekdayLabels[i],
                dayOfMonth: dom,
                isToday: date == today,
                logged: logged,
                planned: planned,
                label: logged.first?.dayLabel ?? planned?.label
            )
        }
    }

    /// The day's VoiceOver name (the fills and rings can't be heard).
    public static func accessibilityLabel(_ day: WeekStripDay) -> String {
        var s = "\(day.weekday) \(day.dayOfMonth)"
        if let label = day.label {
            s += " - \(label)\(day.done ? ", done" : "")"
        } else {
            s += " - rest day"
        }
        if day.isToday { s += ", today" }
        return s + ", open details"
    }

    /// Calibration walkthrough: today's day number inside the window (day 1 = start).
    public static func calibrationDayNumber(start: Date, now: Date = Date(), timeZone: TimeZone = .current) -> Int {
        let midnight = JSDate.localMidnight(JSDate.ms(now), timeZone)
        return Int(JS.round((midnight - JSDate.ms(start)) / JSDate.msPerDay)) + 1
    }
}

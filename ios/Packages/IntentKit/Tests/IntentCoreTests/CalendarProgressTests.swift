import Foundation
import Testing
@testable import IntentCore

// Hand-written tests for the calendar and progress page logic (pages/calendar.tsx,
// components/calendar/MonthGrid.tsx, pages/progress.tsx). That logic lives in React
// components, which the parity fixture generator can't run headless.

private let stockholm = TimeZone(identifier: "Europe/Stockholm")!
private let newYork = TimeZone(identifier: "America/New_York")!

private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, tz: TimeZone = stockholm) -> Date {
    JSDate.date(JSDate.local(Double(y), Double(m - 1), Double(d), Double(h), 0, 0, 0, tz))
}

private func mkSet(_ n: Int, _ w: Double, _ r: Int?, left: Int? = nil, right: Int? = nil, completed: Bool = true) -> LoggedSet {
    LoggedSet(setNumber: n, weight: w, reps: r, repsLeft: left, repsRight: right, completed: completed)
}

@Suite("Calendar month (calendar.tsx / MonthGrid.tsx)")
struct CalendarMonthTests {
    @Test func layoutIsMondayFirst() {
        // 1 Nov 2026 is a Sunday: six blanks before it.
        #expect(CalendarMonth.startPadding(year: 2026, month0: 10, timeZone: stockholm) == 6)
        #expect(CalendarMonth.startPadding(year: 2026, month0: 5, timeZone: stockholm) == 0) // 1 Jun 2026 = Monday
        #expect(CalendarMonth.daysInMonth(year: 2028, month0: 1) == 29)
        #expect(CalendarMonth.monthTitle(year: 2026, month0: 10) == "November 2026")
        let back = CalendarMonth.shiftMonth(year: 2026, month0: 0, by: -1)
        #expect(back.year == 2025 && back.month0 == 11)
        let on = CalendarMonth.shiftMonth(year: 2026, month0: 11, by: 1)
        #expect(on.year == 2027 && on.month0 == 0)
        let days = CalendarMonth.buildDays(year: 2026, month0: 10, todayString: "2026-11-10", sessionsByDate: [:],
                                           ranges: [], activeCalibrationGroup: nil, plannedLabelOn: { _ in nil },
                                           timeZone: stockholm)
        let rows = CalendarMonth.rows(padding: 6, days: days)
        #expect(rows.count == 6)
        #expect(rows[0][6]?.date == "2026-11-01")
        #expect(rows[0][5] == nil)
        #expect(rows[5][0]?.date == "2026-11-30")
    }

    @Test func dayStatesFollowTheWeb() {
        let ranges = [PhaseRange(phase: "bulk", start: local(2026, 10, 19), end: local(2026, 11, 15))]
        let days = CalendarMonth.buildDays(
            year: 2026, month0: 10, todayString: "2026-11-04",
            sessionsByDate: ["2026-11-02": ["Upper A"], "2026-11-05": [nil, "Lower B"]],
            ranges: ranges, activeCalibrationGroup: nil,
            plannedLabelOn: { $0 == "2026-11-03" || $0 == "2026-11-06" || $0 == "2026-11-02" ? "Lower A" : nil },
            timeZone: stockholm)
        let d = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
        #expect(d["2026-11-02"]!.trained && d["2026-11-02"]!.isPast && !d["2026-11-02"]!.planned)
        // A past day with no session is never "planned", even on a schedule slot.
        #expect(!d["2026-11-03"]!.planned)
        #expect(d["2026-11-03"]!.accessibilityLabel == "3 November, bulk phase - rest day")
        #expect(d["2026-11-04"]!.isToday && !d["2026-11-04"]!.isPast)
        #expect(d["2026-11-05"]!.accessibilityLabel == "5 November, bulk phase - 2 sessions: Workout, Lower B")
        #expect(d["2026-11-06"]!.planned)
        // The 1st inside a run carries the name; the run ends on the 15th.
        #expect(d["2026-11-01"]!.phaseNamed && !d["2026-11-01"]!.phaseStart)
        #expect(d["2026-11-15"]!.phaseEnd)
        #expect(d["2026-11-16"]!.phase == nil)
        #expect(d["2026-11-20"]!.accessibilityLabel == "20 November - nothing planned")
    }

    @Test func calibrationHidesOtherPhases() {
        let calib = PhaseRange(phase: "calibration", start: local(2026, 11, 2), end: local(2026, 11, 8))
        let bulk = PhaseRange(phase: "bulk", start: local(2026, 11, 9), end: local(2026, 11, 15))
        let group = Calibration.findCalibrationGroup(Calibration.buildCalibrationGroups([calib, bulk], timeZone: stockholm),
                                                     local(2026, 11, 4))
        #expect(group != nil)
        #expect(CalendarMonth.visiblePhase(on: local(2026, 11, 10), ranges: [calib, bulk], activeCalibrationGroup: group) == nil)
        #expect(CalendarMonth.visiblePhase(on: local(2026, 11, 3), ranges: [calib, bulk], activeCalibrationGroup: group)?.phase == "calibration")
        #expect(CalendarMonth.visiblePhase(on: local(2026, 11, 10), ranges: [calib, bulk], activeCalibrationGroup: nil)?.phase == "bulk")
    }

    @Test func phaseWeekCountsFromTheRangeStart() {
        let bulk = PhaseRange(phase: "bulk", start: local(2026, 10, 19), end: local(2026, 11, 8))
        #expect(CalendarMonth.phaseWeek(bulk, on: local(2026, 10, 19), timeZone: stockholm) == 1)
        #expect(CalendarMonth.phaseWeek(bulk, on: local(2026, 11, 4), timeZone: stockholm) == 3)
        let calib = PhaseRange(phase: "calibration", start: local(2026, 10, 19), end: local(2026, 11, 8))
        #expect(CalendarMonth.phaseWeek(calib, on: local(2026, 11, 4), timeZone: stockholm) == nil)
        let open = PhaseRange(phase: "bulk", start: local(2026, 11, 4), end: CalendarMonth.openEnd(timeZone: stockholm))
        #expect(CalendarMonth.phaseWeek(open, on: local(2026, 11, 4), timeZone: stockholm) == nil)
    }

    @Test func independentModePaintsTheGoalFromToday() {
        let now = local(2026, 11, 4, 15)
        let ranges = CalendarMonth.phaseRanges(isIndependent: true, goal: "lose_weight", programs: [],
                                               onboardingCompletedAt: nil, now: now, timeZone: stockholm)
        #expect(ranges.count == 1)
        #expect(ranges[0].phase == "diet")
        #expect(ranges[0].start == local(2026, 11, 4))
    }

    @Test func bandRunsBreakAtPhaseStarts() {
        func day(_ n: Int, _ phase: String?, start: Bool = false, end: Bool = false, named: Bool = false) -> CalendarMonth.Day {
            CalendarMonth.Day(date: "2026-11-\(n)", day: n, isToday: false, isPast: false, trained: false, planned: false,
                              phase: phase, phaseStart: start, phaseNamed: named, phaseEnd: end, accessibilityLabel: "")
        }
        let cells: [CalendarMonth.Day?] = [nil, day(2, "calibration", start: true, named: true), day(3, "calibration", end: true),
                                           day(4, "bulk", start: true, named: true), day(5, "bulk"), day(6, nil), day(7, "bulk", start: true)]
        let runs = CalendarMonth.bandRuns(cells)
        #expect(runs.count == 3)
        #expect(runs[0] == CalendarMonth.BandRun(from: 1, to: 2, phase: "calibration", start: true, end: true, named: true))
        #expect(runs[1] == CalendarMonth.BandRun(from: 3, to: 4, phase: "bulk", start: true, end: false, named: true))
        #expect(runs[2].from == 6 && runs[2].start)
    }

    @Test func sessionTextHelpers() {
        #expect(CalendarMonth.longDate("2026-10-26", timeZone: stockholm) == "Monday 26 October 2026")
        // Ported web bug: a bare date is UTC midnight, the day before in New York.
        #expect(CalendarMonth.longDate("2026-10-26", timeZone: newYork) == "Sunday 25 October 2026")
        #expect(CalendarMonth.deltaText(2.5, unit: "kg") == "+2.5kg")
        #expect(CalendarMonth.deltaText(-1, unit: " reps") == "-1 reps")
        #expect(CalendarMonth.deltaText(0, unit: "kg") == "–")
        #expect(CalendarMonth.deltaText(0.1 + 0.2, unit: "kg") == "+0.3kg")
        #expect(CalendarMonth.setLabel(mkSet(1, 80, 8)) == "80kg × 8")
        #expect(CalendarMonth.setLabel(mkSet(1, 22.5, nil, left: 8, right: 7)) == "22.5kg × 8L / 7R")
        #expect(CalendarMonth.setReps(mkSet(1, 20, nil, left: 8, right: 7)) == 7)
    }

    @Test func sessionSummaryCountsRealSetsOrTicks() {
        let full = WorkoutLog(id: 1, date: "2026-11-02", exercisesLogged: [
            LoggedExercise(name: "Bench", muscle: "Chest", sets: [mkSet(1, 80, 8), mkSet(2, 0, 0)]),
            LoggedExercise(name: "Row", muscle: "Upper Back", sets: [mkSet(1, 0, nil)]),
            LoggedExercise(name: "Plank", muscle: "", sets: [], kind: .checklist, completedRounds: 2),
        ], durationSeconds: 3720)
        #expect(CalendarMonth.sessionSummary(full) == "1 exercise · 1 set · 1h 02m")
        let calib = WorkoutLog(id: 2, date: "2026-11-02", loggingMode: .calibration, exercisesLogged: [
            LoggedExercise(name: "Bench", muscle: "Chest", sets: [mkSet(1, 0, nil), mkSet(2, 0, nil, completed: false)]),
            LoggedExercise(name: "Plank", muscle: "", sets: [], kind: .checklist),
        ])
        #expect(CalendarMonth.sessionSummary(calib) == "Calibration · 1 exercise · 1 set done")
        #expect(CalendarMonth.modeLabel(calib) == "Calibration")
    }

    @Test func previousSetsSkipEmptySessionsAndLaterOnes() {
        let bench = { (sets: [LoggedSet]) in LoggedExercise(name: "Bench", muscle: "Chest", sets: sets) }
        let old = WorkoutLog(id: 1, date: "2026-10-19", exercisesLogged: [bench([mkSet(1, 75, 8)])])
        let empty = WorkoutLog(id: 2, date: "2026-10-26", exercisesLogged: [bench([mkSet(1, 0, nil)])])
        let current = WorkoutLog(id: 3, date: "2026-11-02", exercisesLogged: [bench([mkSet(1, 80, 8), mkSet(2, 80, 7)])])
        let later = WorkoutLog(id: 4, date: "2026-11-09", exercisesLogged: [bench([mkSet(1, 90, 8)])])
        let all = [later, current, empty, old]
        let prev = CalendarMonth.previousSets(for: "Bench", before: current, in: all)
        #expect(prev == [mkSet(1, 75, 8)])
        let d = CalendarMonth.setDelta(current.exercisesLogged[0].sets[0], previous: prev)
        #expect(d?.weight == 5 && d?.reps == 0)
        #expect(CalendarMonth.setDelta(current.exercisesLogged[0].sets[1], previous: prev) == nil)
        #expect(CalendarMonth.previousSets(for: "Bench", before: old, in: all) == nil)
    }
}

@Suite("Progress page (progress.tsx)")
struct ProgressMathTests {
    @Test func numbers() {
        #expect(ProgressMath.fmt(82.5) == "82.5")
        #expect(ProgressMath.fmt(78.23333) == "78.2")
        #expect(ProgressMath.fmt(80) == "80")
        #expect(ProgressMath.signed(5) == "+5")
        #expect(ProgressMath.signed(-1.25) == "\u{2212}1.3")
        #expect(ProgressMath.signed(0) == "±0")
        #expect(ProgressMath.goalLine(current: 78.4, goalWeight: 84, unit: "kg") == "5.6 kg to go")
        #expect(ProgressMath.goalLine(current: 84.02, goalWeight: 84, unit: "kg") == "Goal reached")
    }

    @Test func chartBounds() {
        #expect(ProgressMath.strengthBounds([80, 82.5, 85]) == ProgressMath.Bounds(lower: 60, upper: 85))
        #expect(ProgressMath.strengthBounds([10, 12]) == ProgressMath.Bounds(lower: 10, upper: 15))
        #expect(ProgressMath.strengthBounds([]) == nil)
        // The goal widens the range so its line stays in frame.
        #expect(ProgressMath.bodyweightBounds([77.1, 78.4], goalWeight: 84) == ProgressMath.Bounds(lower: 74, upper: 86))
        #expect(ProgressMath.bodyweightBounds([77.1, 78.4], goalWeight: nil) == ProgressMath.Bounds(lower: 74, upper: 80))
    }

    @Test func volumeRanking() {
        let w1 = ProgressMath.MuscleWeek(week: 1, sets: ["chest": 6, "quads": 10, "biceps": 4])
        let w2 = ProgressMath.MuscleWeek(week: 2, sets: ["chest": 3, "shoulders": 3, "biceps": 2])
        let ranked = ProgressMath.rankedMuscles(latest: w2, prior: w1)
        #expect(ranked.map(\.key) == ["chest", "shoulders", "biceps"]) // ties keep display order
        #expect(ranked.map(\.change) == [-3, 3, -2])
        #expect(ProgressMath.weekTotal(w1) == 20)
        let weeks = (1...10).map { ProgressMath.MuscleWeek(week: $0, sets: ["core": $0]) }
        let totals = ProgressMath.weeklyTotals(weeks)
        #expect(totals.count == 8 && totals.first?.week == 3 && totals.last?.sets == 10)
    }

    @Test func recentRecords() {
        let now = local(2026, 11, 4, 12)
        let prs = [PersonalRecord(exercise: "Bench", maxWeight: 85, reps: 7, date: "2026-11-02"),
                   PersonalRecord(exercise: "Squat", maxWeight: 105, reps: 6, date: "2026-10-27"),
                   PersonalRecord(exercise: "Row", maxWeight: 31, reps: 9, date: "2026-10-29")]
        #expect(ProgressMath.recentPrCount(prs, now: now, timeZone: stockholm) == 2)
        #expect(ProgressMath.sortedRecords(prs).map(\.exercise) == ["Bench", "Row", "Squat"])
        #expect(ProgressMath.shortDate("2026-11-02", timeZone: stockholm) == "2 Nov")
        #expect(ProgressMath.shortDateWithYear("2026-11-02", timeZone: stockholm) == "2 Nov 2026")
    }
}

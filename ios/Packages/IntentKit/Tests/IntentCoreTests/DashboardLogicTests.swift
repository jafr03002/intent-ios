import Foundation
import Testing
@testable import IntentCore

@Suite("dashboard logic")
struct DashboardLogicTests {
    let tz = TimeZone(identifier: "Europe/Stockholm")!

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func greeting() {
        #expect(DashboardLogic.greeting(hour: 0) == "Good morning")
        #expect(DashboardLogic.greeting(hour: 11) == "Good morning")
        #expect(DashboardLogic.greeting(hour: 12) == "Good afternoon")
        #expect(DashboardLogic.greeting(hour: 17) == "Good evening")
        #expect(DashboardLogic.greeting(at: at(2026, 11, 4, 9), timeZone: tz) == "Good morning")
    }

    @Test func weekStartIsMonday() {
        // Wed 2026-11-04 -> Mon 11-02; Sun 2026-11-08 -> Mon 11-02; Mon stays.
        #expect(DashboardLogic.startOfWeekDateString(now: at(2026, 11, 4), timeZone: tz) == "2026-11-02")
        #expect(DashboardLogic.startOfWeekDateString(now: at(2026, 11, 8), timeZone: tz) == "2026-11-02")
        #expect(DashboardLogic.startOfWeekDateString(now: at(2026, 11, 2), timeZone: tz) == "2026-11-02")
        #expect(DashboardLogic.todayDateString(now: at(2026, 11, 4), timeZone: tz) == "2026-11-04")
    }

    @Test func daysSinceReadsDateOnlyAsUTC() {
        let now = at(2026, 11, 4, 0) // 2026-11-03T23:00Z
        // new Date("2026-11-03") is UTC midnight: 23h ago -> 0 days.
        #expect(DashboardLogic.daysSince("2026-11-03", now: now, timeZone: tz) == 0)
        #expect(DashboardLogic.daysSince(nil, now: now, timeZone: tz) == .infinity)
        #expect(DashboardLogic.recentPrCount(["2026-11-01", "2026-10-20", ""], now: now, timeZone: tz) == 1)
    }

    @Test func checkinBanner() {
        let now = at(2026, 11, 4)
        let bulk = PhaseRow(shortTermPhase: "bulk", weekInPhase: 3, generatedAt: "2026-10-19T10:00:00.000Z",
                            aiGenerated: true, startDate: "2026-10-19")
        func show(_ rows: [PhaseRow], _ latest: String?, independent: Bool = false, program: Bool = true) -> Bool {
            DashboardLogic.showCheckinBanner(isIndependent: independent, hasProgram: program, programs: rows,
                                             latestCheckinSubmittedAt: latest, onboardingCompletedAt: nil,
                                             now: now, timeZone: tz)
        }
        #expect(show([bulk], "2026-10-27T10:00:00.000Z"))
        #expect(!show([bulk], "2026-11-01T10:00:00.000Z"))
        #expect(show([bulk], nil)) // day-6 nudge from the start date
        #expect(!show([bulk], nil, independent: true))
        #expect(!show([bulk], nil, program: false))
        let calibration = PhaseRow(shortTermPhase: "calibration", weekInPhase: 1, generatedAt: "2026-11-02T10:00:00.000Z",
                                   aiGenerated: true, startDate: "2026-11-02")
        #expect(!show([calibration], nil))
    }

    @Test func weekStrip() {
        let schedule = ProgramSchedule(mode: .fixed, slots: [1, 2, nil, 3, 4, nil, nil])
        let days = [DashboardPlannedDay(dayNumber: 1, label: "Upper A"), DashboardPlannedDay(dayNumber: 2, label: "Lower A"),
                    DashboardPlannedDay(dayNumber: 3, label: "Upper B"), DashboardPlannedDay(dayNumber: 4, label: "Lower B")]
        let week = DashboardLogic.weekStripDays(
            weekStart: "2026-11-02", today: "2026-11-04", schedule: schedule, programStartDate: "2026-10-19",
            days: days, sessions: [DashboardLoggedSession(id: 1, date: "2026-11-02", dayLabel: "Upper A")], timeZone: tz)
        #expect(week.map(\.date) == ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07", "2026-11-08"])
        #expect(week.map(\.dayOfMonth) == [2, 3, 4, 5, 6, 7, 8])
        #expect(week[0].done && week[0].label == "Upper A")
        #expect(!week[1].done && week[1].label == "Lower A")
        #expect(week[2].isToday && week[2].label == nil)
        #expect(DashboardLogic.accessibilityLabel(week[2]) == "Wed 4 - rest day, today, open details")
        #expect(DashboardLogic.accessibilityLabel(week[0]) == "Mon 2 - Upper A, done, open details")

        let rotating = DashboardLogic.weekStripDays(
            weekStart: "2026-11-02", today: "2026-11-04", schedule: ProgramSchedule(mode: .rotating, slots: [1, 2]),
            programStartDate: "2026-10-19", days: days, sessions: [], timeZone: tz)
        #expect(rotating.allSatisfy { $0.planned == nil })
    }

    @Test func arcAndCounts() {
        #expect(DashboardLogic.Arc.y(offset: 0) == 38)
        #expect(abs(DashboardLogic.Arc.y(offset: -3) - 52.4) < 1e-9)
        #expect(DashboardLogic.loggedCount(weight: 80, calories: nil, steps: 0, cardioType: nil) == 2)
        #expect(DashboardLogic.toGo(trendWeight: 78.4, goalWeight: 84).map { abs($0 - 5.6) < 1e-9 } == true)
        let start = at(2026, 11, 2, 0)
        #expect(DashboardLogic.calibrationDayNumber(start: start, now: at(2026, 11, 4, 15), timeZone: tz) == 3)
    }
}

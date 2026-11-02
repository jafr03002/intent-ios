import Foundation
import IntentAPI
import IntentCore
import Observation

/// Everything the dashboard reads, loaded together (the web fires the same queries
/// from pages/dashboard.tsx and WeekStrip.tsx). Missing data (a 404, an error) reads
/// as absent, as `query.data` would on the web.
@MainActor
@Observable
final class DashboardModel {
    var isLoaded = false

    var profile: IntentSchemas.UserProfile?
    var program: IntentSchemas.Program?
    var programs: [IntentSchemas.Program] = []
    var stats: IntentSchemas.WorkoutStats?
    var latestCheckin: IntentSchemas.Checkin?
    var personalRecords: [IntentSchemas.PersonalRecord] = []
    /// Newest first.
    var workouts: [IntentSchemas.WorkoutLog] = []
    var week: IntentSchemas.DailyLogsWeekResult?
    var goal: IntentSchemas.GoalProgress?
    /// Settings' calendar colour overrides, by day label.
    var colorOverrides: [String: String] = [:]

    /// Set once the walkthrough's "Show me around" saved (the mock backend is
    /// stateless, so the refetched profile can't be trusted to carry it).
    var walkthroughFinished = false

    let weekStart: String
    let today: String

    init(now: Date = Date()) {
        weekStart = DashboardLogic.startOfWeekDateString(now: now)
        today = DashboardLogic.todayDateString(now: now)
    }

    func load(_ client: IntentAPIClient) async {
        let api = client.api
        let weekStart = self.weekStart
        async let profile = try? await api.getProfile().ok.body.json
        async let program = try? await api.getCurrentProgram().ok.body.json
        async let programs = try? await api.listPrograms().ok.body.json
        async let stats = try? await api.getWorkoutStats().ok.body.json
        async let latest = try? await api.getLatestCheckin().ok.body.json
        async let prs = try? await api.getPersonalRecords().ok.body.json
        async let workouts = try? await api.listWorkouts(query: .init(limit: 200)).ok.body.json
        async let week = try? await api.getDailyLogsWeek(query: .init(startDate: weekStart)).ok.body.json
        async let goal = try? await api.getGoalProgress().ok.body.json
        async let colors = try? await api.getCalendarColors().ok.body.json

        self.profile = await profile
        self.program = await program
        self.programs = await programs ?? []
        self.stats = await stats
        self.latestCheckin = await latest
        self.personalRecords = await prs ?? []
        self.workouts = await workouts ?? []
        self.week = await week
        self.goal = await goal
        var overrides: [String: String] = [:]
        for c in await colors ?? [] { overrides[c.dayLabel] = c.hexColor }
        self.colorOverrides = overrides
        isLoaded = true
    }

    func reloadGoalAndProfile(_ client: IntentAPIClient) async {
        let api = client.api
        async let goal = try? await api.getGoalProgress().ok.body.json
        async let profile = try? await api.getProfile().ok.body.json
        self.goal = await goal
        if let p = await profile { self.profile = p }
    }

    func reloadProgram(_ client: IntentAPIClient) async {
        let api = client.api
        async let program = try? await api.getCurrentProgram().ok.body.json
        async let programs = try? await api.listPrograms().ok.body.json
        async let profile = try? await api.getProfile().ok.body.json
        self.program = await program
        self.programs = await programs ?? self.programs
        if let p = await profile { self.profile = p }
    }

    // MARK: Derived

    var isIndependent: Bool { profile?.mode == "independent" }

    var todayEntry: IntentSchemas.DailyLogWeekEntry? {
        week?.days.first { $0.date == today }
    }

    func entry(for date: String) -> IntentSchemas.DailyLogWeekEntry? {
        week?.days.first { $0.date == date }
    }

    /// The AI lineage maths reads these fields of every program row.
    var phaseRows: [PhaseRow] { programs.map(dashboardPhaseRow) }

    var coreProgramDays: [DashboardPlannedDay] {
        (program?.days ?? []).map { DashboardPlannedDay(dayNumber: $0.dayNumber, label: $0.label) }
    }

    var coreSchedule: ProgramSchedule? {
        guard let s = program?.schedule else { return nil }
        return ProgramSchedule(mode: s.mode == .fixed ? .fixed : .rotating, slots: s.slots)
    }

    var weekDays: [WeekStripDay] {
        DashboardLogic.weekStripDays(
            weekStart: weekStart, today: today, schedule: coreSchedule, programStartDate: program?.startDate,
            days: coreProgramDays,
            sessions: workouts.map { DashboardLoggedSession(id: $0.id, date: $0.date, dayLabel: $0.dayLabel) })
    }

    /// Same positional order the program page and calendar use.
    func dayColorHex(_ label: String) -> String {
        let order = DayColors.buildDayColorOrder(programLabels: (program?.days ?? []).map(\.label),
                                                 extraLabels: workouts.map(\.dayLabel))
        return DayColors.dayColorHex(label, order: order, custom: colorOverrides)
    }

    /// The session the client is up to: the one after whatever they last finished.
    var nextDay: DashboardPlannedDay? {
        GreetingLines.nextSessionDay(coreProgramDays, lastCompletedDayNumber: workouts.first?.dayNumber)
    }

    var showCheckinBanner: Bool {
        DashboardLogic.showCheckinBanner(
            isIndependent: isIndependent, hasProgram: program != nil, programs: phaseRows,
            latestCheckinSubmittedAt: latestCheckin?.submittedAt,
            onboardingCompletedAt: profile?.onboardingCompletedAt)
    }

    var recentPrCount: Int { DashboardLogic.recentPrCount(personalRecords.map(\.date)) }

    var isPreCalibrationLocked: Bool {
        guard let program else { return false }
        return Calibration.isPreCalibrationLocked(aiGenerated: program.aiGenerated, startDate: program.startDate, today: Date())
    }

    /// The calibration window's first day when the one-time walkthrough is due.
    var walkthroughStart: Date? {
        guard let profile, !isIndependent, !walkthroughFinished else { return nil }
        let rows = phaseRows
        guard Calibration.shouldShowCalibrationWalkthrough(
            rows, onboardingCompletedAt: profile.onboardingCompletedAt,
            calibrationWalkthroughSeenAt: profile.calibrationWalkthroughSeenAt, today: Date()) else { return nil }
        let groups = Calibration.buildCalibrationGroups(
            Calibration.buildPhaseRanges(rows, onboardingCompletedAt: profile.onboardingCompletedAt))
        return Calibration.findCalibrationGroup(groups, Date())?.start
    }

    var isCalibrationProgram: Bool {
        Calibration.isCalibrationProgram(aiGenerated: program?.aiGenerated, shortTermPhase: program?.shortTermPhase?.rawValue)
    }
}

func dashboardPhaseRow(_ p: IntentSchemas.Program) -> PhaseRow {
    PhaseRow(shortTermPhase: p.shortTermPhase?.rawValue, weekInPhase: p.weekInPhase, generatedAt: p.generatedAt,
             aiGenerated: p.aiGenerated, startDate: p.startDate)
}

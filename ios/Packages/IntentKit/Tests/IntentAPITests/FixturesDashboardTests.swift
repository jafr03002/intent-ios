import Foundation
import Testing
@testable import IntentAPI

/// The Dashboard feature's fixtures (default ops it owns + its scenarios) must decode
/// through the generated client.
@Suite struct FixturesDashboardTests {
    func client(_ scenario: String = "default") -> IntentAPIClient {
        IntentAPIClient(environment: .production, transport: FixtureTransport(scenario: scenario, latency: .zero))
    }

    @Test func defaultDashboardFixturesDecode() async throws {
        let api = client().api
        #expect(try await api.getWorkoutStats().ok.body.json.currentWeek == 3)
        let week = try await api.getDailyLogsWeek(query: .init(startDate: "2026-11-02")).ok.body.json
        #expect(week.days.count == 8)
        #expect(week.shortTermPhase == .bulk)
        #expect(try await api.getTodaysBodyweight(query: .init(date: "2026-11-02")).ok.body.json.weight == 78.6)
        _ = try await api.logBodyweight(body: .json(.init(date: "2026-11-02", weight: 78.6))).ok.body.json
        let saved = try await api.submitDailyCheckin(body: .json(.init(date: "2026-11-02", calories: 1420))).ok.body.json
        #expect(saved.bodyweightLog?.weight == 78.6)
        #expect(try await api.getLatestCheckin().ok.body.json.ratingScaleMax == 5)
        #expect(try await api.getCheckinAdherence().ok.body.json.plannedSessions == 4)
        #expect(try await api.getGoalProgress().ok.body.json.goalWeight == 84)
        // Shared fixture owned by Progress (computed from the history): 22 records.
        #expect(try await api.getPersonalRecords().ok.body.json.count == 22)
    }

    @Test func independentScenarioDecodes() async throws {
        let api = client("independent").api
        let profile = try await api.getProfile().ok.body.json
        #expect(profile.mode == "independent")
        #expect(profile.cardioDays == ["Tue", "Thu", "Sat"])
        let program = try await api.getCurrentProgram().ok.body.json
        #expect(program.aiGenerated == false)
        #expect(program.days.map(\.label) == ["Push", "Pull", "Legs"])
        #expect(try await api.listPrograms().ok.body.json.count == 1)
        #expect(try await api.listWorkouts().ok.body.json.allSatisfy { $0.mode == .independent })
        _ = try await api.updateProfile(body: .json(.init(dailyCalorieTarget: 2300))).ok.body.json
        if case .ok = try await api.getLatestCheckin() { Issue.record("independent has no check-ins") }
    }

    @Test func calibrationScenariosDecode() async throws {
        for scenario in ["dashboard-calibration", "dashboard-calibration-intro", "dashboard-precalibration"] {
            let api = client(scenario).api
            let program = try await api.getCurrentProgram().ok.body.json
            #expect(program.shortTermPhase == .calibration, "\(scenario)")
            #expect(try await api.listPrograms().ok.body.json.count == 1)
            _ = try await api.getProfile().ok.body.json
            _ = try await api.listWorkouts().ok.body.json
            _ = try await api.getWorkoutStats().ok.body.json
            #expect(try await api.getDailyLogsWeek(query: .init(startDate: "2026-11-02")).ok.body.json.shortTermPhase == .calibration)
            #expect(try await api.getGoalProgress().ok.body.json.targetDate == nil)
            #expect(try await api.getPersonalRecords().ok.body.json.isEmpty)
        }
        let intro = try await client("dashboard-calibration-intro").api.getProfile().ok.body.json
        #expect(intro.calibrationWalkthroughSeenAt == nil)
        let moved = try await client("dashboard-precalibration").api
            .setProgramStartDate(path: .init(id: 31), body: .json(.init(startDate: "2026-11-02"))).ok.body.json
        #expect(moved.id == 31)
    }

    @Test func noProgramScenario() async throws {
        let api = client("dashboard-noprogram").api
        if case .ok = try await api.getCurrentProgram() { Issue.record("expected no program") }
        #expect(try await api.listPrograms().ok.body.json.isEmpty)
        #expect(try await api.getWorkoutStats().ok.body.json.totalLogged == 0)
    }
}

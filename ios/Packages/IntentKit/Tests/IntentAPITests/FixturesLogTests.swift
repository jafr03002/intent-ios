import Foundation
import Testing
@testable import IntentAPI

/// The Log feature's fixtures (default writes + session-review reads, and the
/// `calibration` scenario) must decode through the generated client.
@Suite struct FixturesLogTests {
    let defaultClient = IntentAPIClient(environment: .production, transport: FixtureTransport(latency: .zero))
    let calibrationClient = IntentAPIClient(environment: .production,
                                            transport: FixtureTransport(scenario: "calibration", latency: .zero))

    private func sampleInput() -> IntentSchemas.WorkoutLogInput {
        IntentSchemas.WorkoutLogInput(
            date: "2026-11-01", dayNumber: 2, weekNumber: 3, dayLabel: "Lower A",
            exercisesLogged: [.init(name: "Back Squat", muscle: "Quads",
                                    sets: [.init(setNumber: 1, weight: 100, reps: 6, completed: true)])],
            loggingMode: .full)
    }

    @Test func defaultLogFixturesDecode() async throws {
        let saved = try await defaultClient.api.createWorkout(body: .json(sampleInput())).created.body.json
        #expect(saved.id == 310)
        #expect(saved.dayLabel == "Lower A")
        #expect(saved.date.count == 10)

        let upperA = try await defaultClient.api.getWorkoutsByDayLabel(query: .init(label: "Upper A")).ok.body.json
        #expect(upperA.count == 3)
        #expect(upperA.allSatisfy { $0.dayLabel == "Upper A" })

        let stats = try await defaultClient.api.getSessionDurationStats().ok.body.json
        #expect(stats.stats.count == 4)
        #expect(stats.stats.first?.sampleCount == 3)
    }

    @Test func calibrationScenarioDecodes() async throws {
        let program = try await calibrationClient.api.getCurrentProgram().ok.body.json
        #expect(program.id == 20)
        #expect(program.aiGenerated)
        #expect(program.shortTermPhase == .calibration)
        #expect(program.days.count == 4)
        #expect(program.startDate?.count == 10)

        let programs = try await calibrationClient.api.listPrograms().ok.body.json
        #expect(programs.count == 1)

        let profile = try await calibrationClient.api.getProfile().ok.body.json
        #expect(profile.name == "Alex")
        #expect(profile.userId == "user_mock_alex")
        #expect(profile.calibrationBriefingSeenAt != nil)

        let status = try await calibrationClient.api.getCalibrationStatus().ok.body.json
        #expect(status.inCalibration)
        #expect(status.calibrationDay == 4)
        #expect(status.sessions.count == 1)
        #expect(status.checks?.allMet == false)

        let history = try await calibrationClient.api.listWorkouts().ok.body.json
        #expect(history.count == 1)
        #expect(history.first?.loggingMode == .calibration)
        #expect(history.first?.exercisesLogged.allSatisfy { ex in ex.sets.allSatisfy { $0.weight == 0 } } == true)
        #expect(try await calibrationClient.api.getRecentWorkouts().ok.body.json.count == 1)
        #expect(try await calibrationClient.api.getWorkoutsByDayLabel(query: .init(label: "Upper A")).ok.body.json.count == 1)
        #expect(try await calibrationClient.api.getSessionDurationStats().ok.body.json.stats.isEmpty)

        let saved = try await calibrationClient.api.createWorkout(body: .json(sampleInput())).created.body.json
        #expect(saved.loggingMode == .calibration)
    }
}

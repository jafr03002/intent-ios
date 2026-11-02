import Foundation
import Testing
@testable import IntentAPI

/// The calendar and progress screens' fixtures (scenario "default") decode through
/// the generated client and agree with the shared workout history in listWorkouts.json.
@Suite struct FixturesProgressTests {
    let client = IntentAPIClient(environment: .production, transport: FixtureTransport(latency: .zero))

    @Test func calendarFixturesDecode() async throws {
        let colors = try await client.api.getCalendarColors().ok.body.json
        #expect(colors.map(\.dayLabel) == ["Lower B"])
        #expect(colors.allSatisfy { $0.hexColor.count == 7 && $0.hexColor.hasPrefix("#") })
        let saved = try await client.api.upsertCalendarColor(body: .json(.init(dayLabel: "Lower B", hexColor: "#f97316"))).ok.body.json
        #expect(saved.dayLabel == "Lower B")
        _ = try await client.api.deleteWorkout(path: .init(id: 309)).noContent
    }

    @Test func progressFixturesDecode() async throws {
        let volume = try await client.api.getVolumeProgress().ok.body.json
        #expect(volume.map(\.week) == [1, 2, 3])
        let muscle = try await client.api.getMuscleVolumeBreakdown().ok.body.json
        #expect(muscle.map(\.week) == [1, 2, 3])
        #expect(muscle.last?.chest == 3)
        let strength = try await client.api.getStrengthProgress(query: .init(exercise: "Barbell Bench Press")).ok.body.json
        #expect(strength.map(\.maxWeight) == [80, 82.5, 85])
        #expect(strength.allSatisfy { $0.date.count == 10 })
        let prs = try await client.api.getPersonalRecords().ok.body.json
        #expect(prs.count == 22)
        #expect(prs.first { $0.exercise == "Barbell Bench Press" }?.maxWeight == 85)
        let tracked = try await client.api.listTrackedExercises().ok.body.json
        #expect(tracked.contains("Barbell Bench Press"))
        #expect(tracked == tracked.sorted())
        let bodyweight = try await client.api.getBodyweightProgress().ok.body.json
        #expect(bodyweight.last?.weight == 78.4)
        let goal = try await client.api.getGoalProgress().ok.body.json
        #expect(goal.goalWeight == 84)
        #expect(goal.targetDate?.count == 10)
    }

    /// Every lift in the shared history has a PR row and a tracked-exercise entry.
    @Test func progressMatchesTheSharedHistory() async throws {
        let workouts = try await client.api.listWorkouts().ok.body.json
        let lifts = Set(workouts.flatMap { $0.exercisesLogged.filter { $0.kind != .checklist }.map(\.name) })
        let prs = Set(try await client.api.getPersonalRecords().ok.body.json.map(\.exercise))
        #expect(prs == lifts)
        let all = Set(workouts.flatMap { $0.exercisesLogged.map(\.name) })
        #expect(Set(try await client.api.listTrackedExercises().ok.body.json) == all)
        let weeks = Set(workouts.map(\.weekNumber))
        #expect(Set(try await client.api.getVolumeProgress().ok.body.json.map(\.week)) == weeks)
    }
}

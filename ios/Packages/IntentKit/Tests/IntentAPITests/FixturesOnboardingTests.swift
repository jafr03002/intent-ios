import Foundation
import Testing
@testable import IntentAPI

/// The `onboarding` scenario (a brand-new user: no profile, then a finished program
/// generation job) must decode through the generated client.
@Suite struct FixturesOnboardingTests {
    let client = IntentAPIClient(environment: .production,
                                 transport: FixtureTransport(scenario: "onboarding", latency: .zero))

    @Test func profileIsMissing() async throws {
        let response = try await client.api.getProfile()
        guard case .notFound = response else {
            Issue.record("expected 404, got \(response)")
            return
        }
    }

    @Test func createAndUpdateProfile() async throws {
        let input = IntentSchemas.UserProfileInput(name: "Sam", mode: "ai", goal: "gain_weight", experience: "intermediate",
                                                   trainingDays: 4, equipment: ["Full gym"], weightUnit: "kg")
        let created = try await client.api.createProfile(body: .json(input)).created.body.json
        #expect(created.name == "Sam")
        #expect(created.onboardingComplete)
        #expect(created.mode == "ai")

        let updated = try await client.api.updateProfile(body: .json(.init(trainingDays: 3))).ok.body.json
        #expect(updated.userId == "user_mock_sam")
    }

    @Test func generationJobFinishesWithAProgram() async throws {
        let accepted = try await client.api.startProgramGenerationJob(body: .json(.init())).accepted.body.json
        #expect(accepted.jobId == "job_mock_onboarding")

        let job = try await client.api.getProgramGenerationJob(path: .init(jobId: accepted.jobId)).ok.body.json
        #expect(job.status == .succeeded)
        let program = try #require(job.result)
        #expect(program.id == 30)
        #expect(program.shortTermPhase == .calibration)
        #expect(program.days.count == 4)
        #expect(program.schedule?.mode == .fixed)
        #expect(program.startDate == nil)
        #expect(program.longTermGoalWeight == 80)
    }

    @Test func startDateAndCurrentProgram() async throws {
        let started = try await client.api.setProgramStartDate(path: .init(id: 30),
                                                               body: .json(.init(startDate: "2026-11-02"))).ok.body.json
        #expect(started.startDate?.count == 10)
        let current = try await client.api.getCurrentProgram().ok.body.json
        #expect(current.id == 30)
    }
}

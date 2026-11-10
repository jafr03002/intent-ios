import Foundation
import Testing
@testable import IntentAPI

/// The weekly check-in's fixtures (scenarios "checkin" and "checkin-locked") decode
/// through the generated client and tell one consistent story.
@Suite struct FixturesCheckinTests {
    let client = IntentAPIClient(environment: .production, transport: FixtureTransport(scenario: "checkin", latency: .zero))
    let locked = IntentAPIClient(environment: .production, transport: FixtureTransport(scenario: "checkin-locked", latency: .zero))

    @Test func checkinFixturesDecode() async throws {
        let programs = try await client.api.listPrograms().ok.body.json
        #expect(programs.map(\.id) == [23, 22, 21, 20])
        #expect(programs.last?.shortTermPhase == .calibration)
        #expect(programs.allSatisfy { $0.aiGenerated })
        let current = try await client.api.getCurrentProgram().ok.body.json
        #expect(current.id == 23)

        let all = try await client.api.listCheckins().ok.body.json
        #expect(all.map(\.id) == [32, 31])
        let latest = try await client.api.getLatestCheckin().ok.body.json
        #expect(latest.id == 32)
        #expect(latest.ratingScaleMax == 5)
        // The latest check-in comes after the review (the first bulk row).
        #expect(latest.submittedAt > programs[2].generatedAt)

        let adherence = try await client.api.getCheckinAdherence().ok.body.json
        #expect(adherence.loggedSessions == 3 && adherence.plannedSessions == 4)
        #expect(adherence.missingDays.map(\.label) == ["Lower B"])
        #expect(adherence.loggedDays.allSatisfy { $0.date?.count == 10 })

        let input = IntentSchemas.CheckinInput(energy: 4, sleep: 3, soreness: "moderate", hungerAppetite: 4,
                                               offDayDeviation: false, missedSessionReason: .forgotToLog)
        let blocking = try await client.api.submitCheckin(body: .json(input)).created.body.json
        #expect(!blocking.aiMessage.isEmpty)
        let accepted = try await client.api.startCheckinJob(body: .json(input)).accepted.body.json
        let job = try await client.api.getCheckinJob(path: .init(jobId: accepted.jobId)).ok.body.json
        #expect(job.jobId == accepted.jobId)
        #expect(job.status == .succeeded)
        #expect(job.error == nil)
        let result = try #require(job.result)
        #expect(result.aiMessage == blocking.aiMessage)
        #expect(result.aiMessage.contains("Alex"))
        #expect(result.updatedProgram.weekInPhase == 4)
        #expect(result.updatedProgram.dailyCalorieTarget == 3250)
        #expect(result.checkin.missedSessionReason == "forgot_to_log")
    }

    @Test func lockedFixturesDecode() async throws {
        let programs = try await locked.api.listPrograms().ok.body.json
        #expect(programs.map(\.shortTermPhase) == [.bulk, .calibration])
        guard case .notFound = try await locked.api.getLatestCheckin() else {
            Issue.record("expected 404 for getLatestCheckin")
            return
        }
        #expect(try await locked.api.listCheckins().ok.body.json.isEmpty)
    }
}

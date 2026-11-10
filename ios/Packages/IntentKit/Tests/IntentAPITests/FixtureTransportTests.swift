import Foundation
import HTTPTypes
import Testing
@testable import IntentAPI

/// The mock backend must stay decodable by the generated client: a fixture that drifts
/// from openapi.yaml would make a screen look broken (or fine) for the wrong reason.
/// When you add a fixture for a new operation, add a call for it here.
@Suite struct FixtureTransportTests {
    let client = IntentAPIClient(environment: .production, transport: FixtureTransport(latency: .zero))

    @Test func sharedFixturesDecode() async throws {
        let profile = try await client.api.getProfile().ok.body.json
        #expect(profile.name == "Alex")
        let program = try await client.api.getCurrentProgram().ok.body.json
        #expect(program.days.count == 4)
        #expect(program.schedule?.slots.count == 7)
        #expect(try await client.api.listPrograms().ok.body.json.count == 2)
        let workouts = try await client.api.listWorkouts().ok.body.json
        #expect(workouts.count == 9)
        #expect(workouts.allSatisfy { $0.date.count == 10 })
        #expect(try await client.api.getRecentWorkouts().ok.body.json.count == 3)
        #expect(try await client.api.getCalibrationStatus().ok.body.json.inCalibration == false)
        #expect(try await client.api.getSubscription().ok.body.json.status == "active")
        #expect(try await client.api.healthCheck().ok.body.json.status == "ok")
    }

    @Test func missingFixtureIs404() async throws {
        // A made-up operation, so features adding fixtures never break this.
        let (response, _) = try await FixtureTransport(latency: .zero).send(
            HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/nope"),
            body: nil, baseURL: URL(string: "https://example.com")!, operationID: "noSuchOperation")
        #expect(response.status.code == 404)
    }

    @Test func dowTokensLandOnTheRightWeekday() {
        var cal = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "Europe/Stockholm")!
        cal.timeZone = tz
        // Wednesday 2026-11-04 12:00 Stockholm.
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        let text = FixtureTransport.expandTokens(
            "{{dow:mon:0}} {{dow:fri:-1}} {{date:-3}} {{dow:sun:0}}", now: now, timeZone: tz)
        #expect(text == "2026-11-02 2026-10-30 2026-11-01 2026-11-08")
    }
}

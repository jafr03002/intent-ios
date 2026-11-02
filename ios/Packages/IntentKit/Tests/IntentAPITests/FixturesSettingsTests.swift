import Foundation
import Testing
@testable import IntentAPI

/// The Settings and Nutrition screens' fixtures decode through the generated client:
/// the default writes (updateProfile, deleteAccount, checkout/portal) and the
/// "settings-independent" scenario (Independent mode, manual program, free plan).
@Suite struct FixturesSettingsTests {
    let client = IntentAPIClient(environment: .production, transport: FixtureTransport(latency: .zero))
    let independent = IntentAPIClient(environment: .production,
                                      transport: FixtureTransport(scenario: "settings-independent", latency: .zero))

    @Test func settingsWritesDecode() async throws {
        let saved = try await client.api.updateProfile(body: .json(.init(name: "Alex", age: 27, weight: 78.4, weightUnit: "kg"))).ok.body.json
        #expect(saved.name == "Alex")
        #expect(saved.mode == "ai")
        _ = try await client.api.deleteAccount().noContent
        let checkout = try await client.api.createCheckoutSession(
            body: .json(.init(plan: "pro", successUrl: "intent://upgraded", cancelUrl: "intent://settings"))).ok.body.json
        #expect(checkout.url.hasPrefix("https://"))
        let portal = try await client.api.createPortalSession().ok.body.json
        #expect(portal.url.hasPrefix("https://"))
    }

    @Test func defaultSettingsReads() async throws {
        let sub = try await client.api.getSubscription().ok.body.json
        #expect(sub.plan == "pro")
        #expect(sub.currentPeriodEnd != nil)
        let program = try await client.api.getCurrentProgram().ok.body.json
        #expect(program.dailyCalorieTarget == 3100)
    }

    @Test func independentScenarioDecodes() async throws {
        let profile = try await independent.api.getProfile().ok.body.json
        #expect(profile.mode == "independent")
        #expect(profile.dailyCalorieTarget == 2600)
        let saved = try await independent.api.updateProfile(body: .json(.init(mode: "independent"))).ok.body.json
        #expect(saved.mode == "independent")
        let program = try await independent.api.getCurrentProgram().ok.body.json
        #expect(program.aiGenerated == false)
        #expect(program.days.map(\.label) == ["Upper A", "Lower A", "Upper B"])
        let sub = try await independent.api.getSubscription().ok.body.json
        #expect(sub.plan == "free")
        #expect(sub.currentPeriodEnd == nil)
        // Unchanged reads fall back to default/.
        let colors = try await independent.api.getCalendarColors().ok.body.json
        #expect(colors.map(\.dayLabel) == ["Lower B"])
    }
}

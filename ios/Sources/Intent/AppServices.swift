import Foundation
import IntentAPI
import IntentAuth
import Observation

/// The app's long-lived services, created once at launch and shared through the
/// SwiftUI environment (`@Environment(AppServices.self)`). Clerk can only be configured
/// once per process, so nothing else may create an `AuthSession`.
///
/// Mock mode (`-IntentMock`, optionally `-IntentMockScenario <name>`): the API answers
/// from bundled fixtures (IntentAPI's FixtureTransport) and the sign-in gate is skipped,
/// so every screen renders with realistic data on the CI simulator.
@MainActor
@Observable
final class AppServices {
    let auth: AuthSession
    let api: IntentAPIClient
    let isMock: Bool
    let mockScenario: String

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let auth = AuthSession(instance: .production)
        self.auth = auth
        isMock = arguments.contains("-IntentMock")
        if let i = arguments.firstIndex(of: "-IntentMockScenario"), arguments.indices.contains(i + 1) {
            mockScenario = arguments[i + 1]
        } else {
            mockScenario = "default"
        }
        if isMock {
            api = IntentAPIClient(environment: .production, transport: FixtureTransport(scenario: mockScenario))
        } else {
            // Ask Clerk per request: it caches the token (60s lifetime) and refreshes it.
            api = IntentAPIClient(environment: .production, tokenProvider: auth.tokenProvider)
        }
    }
}

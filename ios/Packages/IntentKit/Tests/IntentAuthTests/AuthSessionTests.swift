import Observation
import Testing
@testable import IntentAuth

/// Stands in for Clerk: settable state, counts token requests.
@MainActor
@Observable
final class FakeAuthBackend: AuthBackend {
    var state: AuthState
    var token: String?
    var tokenError: (any Error)?
    private(set) var tokenRequests = 0

    init(state: AuthState, token: String? = nil) {
        self.state = state
        self.token = token
    }

    func sessionToken() async throws -> String? {
        tokenRequests += 1
        if let tokenError { throw tokenError }
        return token
    }

    func signOut() async throws {
        state = .signedOut
    }
}

struct TokenFailure: Error {}

private let jakob = AuthUser(id: "user_123", email: "jakob@example.com")

@MainActor
struct AuthSessionTests {
    @Test func tokenIsNilWhileLoadingOrSignedOut() async throws {
        for state in [AuthState.loading, .signedOut] {
            let backend = FakeAuthBackend(state: state, token: "should-not-be-used")
            let session = AuthSession(backend: backend)
            #expect(try await session.sessionToken() == nil)
            #expect(backend.tokenRequests == 0)
        }
    }

    @Test func signedInReturnsBackendToken() async throws {
        let backend = FakeAuthBackend(state: .signedIn(jakob), token: "jwt-1")
        let session = AuthSession(backend: backend)
        #expect(session.state.user == jakob)
        #expect(try await session.sessionToken() == "jwt-1")
        backend.token = "jwt-2"
        #expect(try await session.sessionToken() == "jwt-2")
        #expect(backend.tokenRequests == 2)
    }

    @Test func tokenProviderIsSendableAndCallableOffMainActor() async throws {
        let backend = FakeAuthBackend(state: .signedIn(jakob), token: "jwt")
        let provider = AuthSession(backend: backend).tokenProvider
        // The shape IntentAPI takes; run it from a non-main context.
        let fromDetached = try await Task.detached { try await provider() }.value
        #expect(fromDetached == "jwt")
    }

    @Test func tokenErrorsPropagate() async {
        let backend = FakeAuthBackend(state: .signedIn(jakob))
        backend.tokenError = TokenFailure()
        let session = AuthSession(backend: backend)
        await #expect(throws: TokenFailure.self) { try await session.sessionToken() }
    }

    @Test func signOutClearsStateAndToken() async throws {
        let backend = FakeAuthBackend(state: .signedIn(jakob), token: "jwt")
        let session = AuthSession(backend: backend)
        try await session.signOut()
        #expect(session.state == .signedOut)
        #expect(try await session.sessionToken() == nil)
    }

    @Test func stateChangesAreObservedThroughSession() async {
        let backend = FakeAuthBackend(state: .loading)
        let session = AuthSession(backend: backend)
        let changed = Flag()
        withObservationTracking { _ = session.state } onChange: { changed.set() }
        backend.state = .signedIn(jakob)
        #expect(changed.value)
        #expect(session.state.isSignedIn)
    }
}

/// Set from observation's @Sendable onChange, which fires synchronously on mutation.
final class Flag: @unchecked Sendable {
    private(set) var value = false
    func set() { value = true }
}

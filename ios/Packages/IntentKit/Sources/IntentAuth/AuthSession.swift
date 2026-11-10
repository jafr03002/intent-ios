import Observation

/// The seam between AuthSession and Clerk, so the session logic is testable (and
/// builds on Linux) without the SDK. Implementations are expected to be observable:
/// SwiftUI re-renders when `state` changes because AuthSession reads it through.
@MainActor
protocol AuthBackend: AnyObject {
    var state: AuthState { get }
    func sessionToken() async throws -> String?
    func signOut() async throws
    /// Deletes the signed-in Clerk user (Apple requires in-app account deletion).
    func deleteUser() async throws
}

extension AuthBackend {
    func deleteUser() async throws {}
}

/// The app's single handle on authentication. Create one at launch, put it in the
/// SwiftUI environment, and hand `tokenProvider` to the API client.
///
/// ```swift
/// let auth = AuthSession(instance: .production)
/// let api = APIClient(baseURL: ..., token: auth.tokenProvider)
/// ```
@MainActor
@Observable
public final class AuthSession {
    @ObservationIgnored let backend: any AuthBackend

    /// Configures Clerk with the instance's publishable key and starts loading the
    /// stored session. Clerk can only be configured once per process: create one
    /// AuthSession for the app's lifetime.
    public convenience init(instance: ClerkInstance) {
        self.init(publishableKey: instance.publishableKey)
    }

    public convenience init(publishableKey: String) {
        #if canImport(ClerkKit)
        self.init(backend: ClerkAuthBackend(publishableKey: publishableKey))
        #else
        self.init(backend: UnavailableAuthBackend())
        #endif
    }

    init(backend: any AuthBackend) {
        self.backend = backend
    }

    public var state: AuthState { backend.state }

    /// A short-lived JWT for `Authorization: Bearer ...`, or nil when signed out.
    /// Clerk caches it and refreshes it shortly before it expires (60s TTL), so call
    /// this per request rather than storing the result.
    public func sessionToken() async throws -> String? {
        guard state.isSignedIn else { return nil }
        return try await backend.sessionToken()
    }

    /// `sessionToken()` as a Sendable closure, the shape IntentAPI's client takes.
    /// AuthSession is main-actor isolated (hence Sendable), so capturing it is safe;
    /// each call hops to the main actor, and Clerk does the network work off it.
    public nonisolated var tokenProvider: @Sendable () async throws -> String? {
        { [self] in try await self.sessionToken() }
    }

    public func signOut() async throws {
        try await backend.signOut()
    }

    /// Deletes the Clerk user itself (the web's `user.delete()`), after the app's own
    /// data is gone via the API's `deleteAccount`. Clerk ends the session with it.
    public func deleteUser() async throws {
        try await backend.deleteUser()
    }
}

#if !canImport(ClerkKit)
/// Linux (WSL `swift test`) has no Clerk SDK. Always signed out.
@MainActor
final class UnavailableAuthBackend: AuthBackend {
    var state: AuthState { .signedOut }
    func sessionToken() async throws -> String? { nil }
    func signOut() async throws {}
}
#endif

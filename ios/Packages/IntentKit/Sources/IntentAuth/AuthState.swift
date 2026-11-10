/// Who is signed in, as far as the app needs to know. No Clerk types leak out of
/// IntentAuth; the API identifies the user by the session token, not by this.
public struct AuthUser: Equatable, Sendable {
    /// Clerk user id (`user_...`), the same id the API stores as `userId`.
    public let id: String
    public let email: String?
    /// The Clerk profile's first name (set by Google sign-in, or nil). The web shows
    /// it wherever the app profile has no name of its own.
    public let firstName: String?

    public init(id: String, email: String?, firstName: String? = nil) {
        self.id = id
        self.email = email
        self.firstName = firstName
    }
}

public enum AuthState: Equatable, Sendable {
    /// Clerk hasn't loaded its environment + client yet (first launch, or restoring
    /// the session from the keychain).
    case loading
    case signedOut
    case signedIn(AuthUser)

    public var user: AuthUser? {
        if case .signedIn(let user) = self { return user }
        return nil
    }

    public var isSignedIn: Bool { user != nil }
}

/// Which Clerk instance the app signs in against. A token is only accepted by an API
/// server configured with the same instance's keys.
public struct ClerkInstance: Equatable, Sendable {
    public let publishableKey: String

    public init(publishableKey: String) {
        self.publishableKey = publishableKey
    }

    /// The instance behind the deployed web app (trainient-api-server.vercel.app),
    /// so the API in production. It is a Clerk *development* instance
    /// (`calm-sheep-8.clerk.accounts.dev`): there is no `pk_live_` instance yet.
    public static let production = ClerkInstance(
        publishableKey: "pk_test_Y2FsbS1zaGVlcC04LmNsZXJrLmFjY291bnRzLmRldiQ"
    )

    /// The instance the local API server (`artifacts/api-server/.env`) uses
    /// (`new-opossum-13.clerk.accounts.dev`). Use it when pointing the app at a
    /// locally running API.
    public static let localDevelopment = ClerkInstance(
        publishableKey: "pk_test_bmV3LW9wb3NzdW0tMTMuY2xlcmsuYWNjb3VudHMuZGV2JA"
    )
}

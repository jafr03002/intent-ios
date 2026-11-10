#if canImport(ClerkKit)
import ClerkKit
import Foundation

/// AuthBackend over the Clerk iOS SDK (clerk-ios, ClerkKit).
///
/// `Clerk.configure` installs `Clerk.shared` and starts restoring the device's
/// client + session from the keychain and Clerk's Frontend API. `Clerk` is
/// `@Observable`, so `state` (computed from it) is tracked by SwiftUI.
///
/// OAuth (Google) runs in ASWebAuthenticationSession with Clerk's default redirect
/// `com.jakobfreij.Intent://callback`; that needs no Info.plist URL scheme and no
/// paid entitlement, only the redirect allowlisted in the Clerk dashboard.
@MainActor
final class ClerkAuthBackend: AuthBackend {
    let clerk: Clerk

    init(publishableKey: String) {
        clerk = Clerk.configure(
            publishableKey: publishableKey,
            options: .init(logLevel: .warning, telemetryEnabled: false)
        )
    }

    var state: AuthState {
        guard clerk.isLoaded else { return .loading }
        guard let session = clerk.session, session.status == .active,
              let user = session.user ?? clerk.user else { return .signedOut }
        return .signedIn(AuthUser(id: user.id, email: user.primaryEmailAddress?.emailAddress,
                                  firstName: user.firstName))
    }

    func sessionToken() async throws -> String? {
        guard let session = clerk.session, session.status == .active else { return nil }
        return try await session.getToken()
    }

    func signOut() async throws {
        try await clerk.auth.signOut()
    }

    func deleteUser() async throws {
        guard let user = clerk.user else { return }
        _ = try await user.delete()
    }
}
#endif

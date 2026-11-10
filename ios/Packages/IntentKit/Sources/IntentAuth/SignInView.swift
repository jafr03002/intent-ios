#if canImport(SwiftUI) && canImport(ClerkKitUI)
import ClerkKit
import ClerkKitUI
import SwiftUI

/// The sign-in / sign-up screen. For now it's Clerk's prebuilt AuthView, which
/// reads the instance's enabled methods from Clerk (today: email + password with
/// an email code to verify, and Google). It gets a Sessions-style redesign later;
/// callers only ever see this type, so swapping the inside won't touch them.
public struct SignInView: View {
    private let session: AuthSession
    private let onSignedIn: @MainActor () -> Void

    public init(session: AuthSession, onSignedIn: @escaping @MainActor () -> Void = {}) {
        self.session = session
        self.onSignedIn = onSignedIn
    }

    public var body: some View {
        if let clerk = session.clerk {
            AuthView(mode: .signInOrUp, isDismissible: false, onAuthComplete: onSignedIn)
                .environment(clerk)
        } else {
            Text("Sign-in is unavailable on this platform.")
        }
    }
}

extension AuthSession {
    /// The Clerk instance behind this session, for ClerkKitUI views inside IntentAuth.
    var clerk: Clerk? {
        (backend as? ClerkAuthBackend)?.clerk
    }
}
#endif

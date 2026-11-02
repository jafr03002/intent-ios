import IntentAuth
import SwiftUI

/// `-IntentScreen signIn`: the auth state plus the sign-in UI, against the
/// production Clerk instance. On CI nobody is signed in, so it shows the sign-in form.
struct SignInDebugView: View {
    @Environment(AppServices.self) private var services
    private var auth: AuthSession { services.auth }
    @State private var tokenStatus = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("auth: \(describe(auth.state))")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.horizontal, 24)
                switch auth.state {
                case .loading:
                    ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .signedOut:
                    SignInView(session: auth)
                case .signedIn:
                    signedIn
                }
            }
        }
        .onChange(of: auth.state) { _, state in
            appLog.info("auth state: \(describe(state), privacy: .public)")
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Fetch session token") {
                Task {
                    do {
                        let token = try await auth.tokenProvider()
                        tokenStatus = token.map { "token ok (\($0.count) chars)" } ?? "no token"
                    } catch {
                        tokenStatus = "token error: \(error.localizedDescription)"
                    }
                }
            }
            Button("Sign out") { Task { try? await auth.signOut() } }
            Text(tokenStatus).foregroundStyle(Color(white: 0.55))
            Spacer()
        }
        .font(.system(size: 17, weight: .light))
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
    }

    private func describe(_ state: AuthState) -> String {
        switch state {
        case .loading: "loading"
        case .signedOut: "signedOut"
        case .signedIn(let user): "signedIn \(user.id) \(user.email ?? "-")"
        }
    }
}

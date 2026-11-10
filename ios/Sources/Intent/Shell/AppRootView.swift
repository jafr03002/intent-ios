import IntentAPI
import IntentAuth
import IntentDesign
import SwiftUI

/// The real app flow: sign-in gate → onboarding gate → tab shell.
/// In mock mode the sign-in gate is skipped.
struct AppRootView: View {
    @Environment(AppServices.self) private var services
    @State private var onboarding: OnboardingGate = .checking
    /// Bumped by "Try again" to re-run the profile check.
    @State private var attempt = 0

    enum OnboardingGate: Equatable { case checking, needed, done, failed(String) }

    /// Identifies who the gate was checked for: a different account (sign out, then a
    /// new sign-up) must be checked from scratch, never inherit the last one's answer.
    private struct CheckKey: Equatable {
        var user: String?
        var attempt: Int
    }

    var body: some View {
        Group {
            if services.isMock || services.auth.state.isSignedIn {
                switch onboarding {
                case .checking: loading
                case .needed: OnboardingScreen(onFinished: { onboarding = .done })
                case .done: MainTabView()
                case .failed(let detail): failed(detail)
                }
            } else if case .signedOut = services.auth.state {
                SignInView(session: services.auth)
            } else {
                loading
            }
        }
        .task(id: CheckKey(user: services.isMock ? "mock" : services.auth.state.user?.id, attempt: attempt)) {
            onboarding = .checking
            guard services.isMock || services.auth.state.isSignedIn else { return }
            onboarding = await checkOnboarding()
        }
    }

    private var loading: some View {
        ZStack {
            Color.intent.background.ignoresSafeArea()
            ProgressView().tint(Color.intent.mutedForeground)
        }
    }

    /// The profile check failed, so we can't tell a new user (onboarding) from an
    /// existing one (the app). Guessing "existing" used to drop brand-new users on an
    /// empty dashboard with no way into onboarding, so ask them to retry instead.
    private func failed(_ detail: String) -> some View {
        ZStack {
            Color.intent.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Couldn't load your profile")
                    .font(.intent(20, .semibold)).foregroundStyle(Color.intent.foreground)
                Text("Check your connection and try again.")
                    .font(.intent(14)).foregroundStyle(Color.intent.mutedForeground)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.intent(12)).foregroundStyle(Color.intent.mutedForeground.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button("Try again") { attempt += 1 }
                    .buttonStyle(.intentPrimary)
                    .padding(.top, 10)
                if !services.isMock {
                    Button("Sign out") { Task { try? await services.auth.signOut() } }
                        .buttonStyle(.intentOutline)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    /// No profile (404) or an unfinished one means onboarding. A profile that exists
    /// but whose body didn't decode still means "onboarded": the server only creates
    /// profiles at the end of onboarding (and stamps them complete).
    private func checkOnboarding() async -> OnboardingGate {
        do {
            switch try await services.api.api.getProfile() {
            case .ok(let ok): return try ok.body.json.onboardingComplete ? .done : .needed
            case .notFound: return .needed
            case .undocumented(let code, let payload):
                let error = await IntentAPIError.undocumented(statusCode: code, payload)
                appLog.error("profile check: \(error.localizedDescription, privacy: .public)")
                return .failed(error.localizedDescription)
            }
        } catch {
            if let status = IntentAPIError.undecodableSuccessStatus(error) {
                appLog.error("profile check: undecodable \(status) body, treating as onboarded: \(String(describing: error), privacy: .public)")
                return .done
            }
            let mapped = IntentAPIError.from(error)
            appLog.error("profile check failed: \(String(describing: error), privacy: .public)")
            return .failed(mapped.localizedDescription)
        }
    }
}

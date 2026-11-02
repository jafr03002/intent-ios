import IntentAPI
import IntentAuth
import IntentDesign
import SwiftUI

/// The real app flow: sign-in gate → onboarding gate → tab shell.
/// In mock mode the sign-in gate is skipped.
struct AppRootView: View {
    @Environment(AppServices.self) private var services
    @State private var onboarding: OnboardingGate = .checking

    enum OnboardingGate { case checking, needed, done }

    var body: some View {
        Group {
            if services.isMock || services.auth.state.isSignedIn {
                switch onboarding {
                case .checking: loading
                case .needed: OnboardingScreen(onFinished: { onboarding = .done })
                case .done: MainTabView()
                }
            } else if case .signedOut = services.auth.state {
                SignInView(session: services.auth)
            } else {
                loading
            }
        }
        .task(id: services.auth.state.isSignedIn || services.isMock) {
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

    /// No profile (404) or an unfinished one means onboarding; on network errors we
    /// let the user in rather than trapping them on a spinner.
    private func checkOnboarding() async -> OnboardingGate {
        do {
            switch try await services.api.api.getProfile() {
            case .ok(let ok): return try ok.body.json.onboardingComplete ? .done : .needed
            case .notFound: return .needed
            default: return .done
            }
        } catch {
            appLog.error("profile check failed: \(String(describing: error), privacy: .public)")
            return .done
        }
    }
}

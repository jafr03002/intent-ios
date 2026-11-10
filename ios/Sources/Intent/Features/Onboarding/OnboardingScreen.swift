import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// Onboarding (pages/onboarding.tsx): the stepped profile form, then for AI mode
/// generating -> the presentation deck -> the start-day commitment. Calls
/// `onFinished()` when the user lands in the app (profile saved; for AI + generate,
/// once the start date is saved). Guided tours are not part of the native app.
struct OnboardingScreen: View {
    var onFinished: () -> Void = {}
    /// A `-IntentScreen onboarding-*` name: opens a given step/phase with sample
    /// answers for the CI screenshots. Nil is the real flow.
    var debug: String?

    @Environment(AppServices.self) private var services
    @State private var model: OnboardingModel?
    @State private var debugDeckPage = 0
    @State private var debugTweaking = false
    @State private var debugPickingOther = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.intent.background.ignoresSafeArea()
            }
        }
        // Full screen, as the web renders /onboarding without the bottom nav. It can
        // be pushed inside the Program tab ("Set up AI coaching"), where the bar
        // otherwise sat over its Continue / Back buttons.
        .hidesIntentTabBar()
        .task {
            guard model == nil else { return }
            let model = OnboardingModel(api: client, onFinished: onFinished)
            self.model = model
            if let debug {
                await OnboardingDebug.seed(model, name: debug, api: client)
                debugDeckPage = OnboardingDebug.deckPage(debug)
                debugTweaking = debug == "onboarding-tweak"
                debugPickingOther = debug == "onboarding-commit-other"
            } else {
                await model.checkResume()
            }
        }
    }

    /// Debug screens read the `onboarding` fixture scenario whatever
    /// -IntentMockScenario says, so the default CI run shows a new user.
    private var client: Client {
        if debug != nil && services.isMock {
            return IntentAPIClient(environment: .production, transport: FixtureTransport(scenario: "onboarding")).api
        }
        return services.api.api
    }

    @ViewBuilder private func content(_ model: OnboardingModel) -> some View {
        switch model.phase {
        case .form:
            OnboardingFormView(model: model)
        case .generating:
            OnboardingGeneratingView()
        case .presentation:
            if let program = model.coreProgram {
                OnboardingDeckView(
                    program: program, goal: model.form.goal, weightUnit: model.form.weightUnit,
                    name: model.form.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil
                        : model.form.name.trimmingCharacters(in: .whitespaces),
                    priorityMuscles: model.form.priorityMuscles,
                    showRegenerateNudge: model.regenerateCount >= 3,
                    error: model.deckError,
                    initialPage: debugDeckPage, initialTweaking: debugTweaking,
                    onSatisfied: { model.phase = .commitment },
                    onSubmitFeedback: { feedback in Task { await model.regenerate(feedback) } })
            } else {
                OnboardingFormView(model: model)
            }
        case .commitment:
            if let program = model.coreProgram {
                OnboardingCommitmentView(program: program, isSaving: model.commitPending, error: model.commitError,
                                         initialPickingOther: debugPickingOther) { date in
                    Task { await model.commit(startDate: date) }
                }
            } else {
                OnboardingFormView(model: model)
            }
        }
    }
}

/// Sample answers for the `onboarding-*` debug screens.
@MainActor
enum OnboardingDebug {
    static let deckPages: [String: Int] = [
        "onboarding-deck": 0, "onboarding-deck-program": 1, "onboarding-deck-journey": 2,
        "onboarding-deck-volume": 3, "onboarding-deck-sessions": 4, "onboarding-deck-happy": 5, "onboarding-tweak": 5,
    ]

    static func deckPage(_ name: String) -> Int { deckPages[name] ?? 0 }

    static func seed(_ model: OnboardingModel, name: String, api: Client) async {
        guard name != "onboarding" else { return }
        var f = OnboardingForm()
        f.mode = name == "onboarding-targets" || name == "onboarding-review-independent" ? "independent" : "ai"
        f.name = "Sam"
        f.age = "26"
        f.weight = "74"
        f.goal = "gain_weight"
        f.goalWeight = "80"
        f.experience = "intermediate"
        f.activityLevel = "moderate"
        f.trainingDays = 4
        f.preferredRestDays = ["wed", "sat", "sun"]
        f.equipment = ["Full gym"]
        f.sex = "male"
        f.priorityMuscles = ["Chest", "Shoulders"]
        model.form = f
        switch name {
        case "onboarding-goal": model.go(to: .goal)
        case "onboarding-goal-weight":
            model.go(to: .goal)
            model.openGoalWeight()
            model.goalWeightDraft = "70"
            model.saveGoalWeight() // below the current 74 kg: shows the direction error
        case "onboarding-days": model.go(to: .trainingDays)
        case "onboarding-rest":
            model.form.trainingDays = 5
            model.form.preferredRestDays = ["wed", "sat", "sun", "mon"]
            model.go(to: .preferredRestDays)
        case "onboarding-equipment":
            model.form.equipment = ["Dumbbells only", "Pull-up bar"]
            model.go(to: .equipment)
        case "onboarding-details":
            model.form.injuries = "Left shoulder clicks on overhead press"
            model.form.injurySeverity = "low"
            model.go(to: .details)
        case "onboarding-muscles": model.go(to: .priorityMuscles)
        case "onboarding-targets":
            model.form.cardioDays = ["Mon", "Thu"]
            model.form.cardioMinutes = "25"
            model.go(to: .targets)
        case "onboarding-review", "onboarding-review-independent":
            if model.form.mode == "independent" { model.go(to: .targets) }
            model.go(to: .review)
        case "onboarding-generating":
            model.go(to: .review)
            model.phase = .generating
        default:
            // Deck / tweak / commit: the finished job's program from the fixtures.
            model.go(to: .review)
            if case .ok(let ok)? = try? await api.getProgramGenerationJob(path: .init(jobId: "debug")),
               let program = try? ok.body.json.result {
                model.setProgram(program)
                model.phase = name.hasPrefix("onboarding-commit") ? .commitment : .presentation
            }
        }
    }
}

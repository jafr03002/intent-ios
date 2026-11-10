import Foundation
import IntentAPI
import IntentCore
import Observation

/// View state for the onboarding flow (pages/onboarding.tsx): the stepped form,
/// then generating -> presentation deck -> start-day commitment. The pure rules
/// (steps, toggles, validation, review rows) live in IntentCore's `OnboardingForm`.
@MainActor
@Observable
final class OnboardingModel {
    enum Phase: Equatable { case form, generating, presentation, commitment }
    enum FinishAction { case generate, later }

    var form = OnboardingForm()
    var step = 0
    var phase: Phase = .form

    /// The generated program, as the API returned it and as IntentCore reads it.
    private(set) var program: Components.Schemas.Program?
    private(set) var coreProgram: IntentCore.Program?
    private(set) var regenerateCount = 0

    // Target-weight sheet: edits a draft, validated and committed on Save.
    var showGoalWeight = false
    var goalWeightDraft = ""
    var goalWeightSaveError: String?

    private(set) var finishAction: FinishAction?
    private(set) var createPending = false
    private(set) var createError = false
    /// Why the save failed (status / server message), shown under the error banner.
    private(set) var createErrorDetail: String?
    private(set) var updateError = false
    private(set) var commitPending = false
    var commitError: String?

    let job: OnboardingProgramJob
    private let api: Client
    private let onFinished: () -> Void
    private var resumeChecked = false
    private var targetsSeeded = false

    init(api: Client, onFinished: @escaping () -> Void) {
        self.api = api
        self.onFinished = onFinished
        self.job = OnboardingProgramJob(api: api)
    }

    // MARK: Steps

    var steps: [OnboardingStep] { form.steps }
    var currentStep: OnboardingStep { steps[min(step, steps.count - 1)] }
    var totalSteps: Int { steps.count }
    /// Until a mode is picked the flow length is unknown: empty bar, hidden count.
    var hasStarted: Bool { !form.mode.isEmpty }
    var progress: Double { hasStarted ? Double(step + 1) / Double(totalSteps) : 0 }
    var isLastStep: Bool { step == totalSteps - 1 }
    var canAdvance: Bool { form.canAdvance(from: currentStep) }
    var isPending: Bool { createPending || job.isPending }

    func next() {
        guard canAdvance, step < totalSteps - 1 else { return }
        step += 1
        seedTargetsIfNeeded()
    }

    func back() {
        guard step > 0 else { return }
        step -= 1
        seedTargetsIfNeeded()
    }

    func go(to target: OnboardingStep) {
        if let i = steps.firstIndex(of: target) { step = i }
        seedTargetsIfNeeded()
    }

    /// First visit to the targets step pre-fills a suggestion.
    private func seedTargetsIfNeeded() {
        guard currentStep == .targets, !targetsSeeded else { return }
        targetsSeeded = true
        form.seedTargets()
    }

    // MARK: Resume

    /// An AI profile missing goal/experience resumes at the goal step with the
    /// basics prefilled. Runs once.
    func checkResume() async {
        guard !resumeChecked else { return }
        resumeChecked = true
        guard case .ok(let ok)? = try? await api.getProfile(), let profile = try? ok.body.json else { return }
        guard OnboardingForm.shouldResume(mode: profile.mode, goal: profile.goal, experience: profile.experience) else { return }
        form.resume(name: profile.name, age: profile.age, sex: profile.sex, weight: profile.weight,
                    weightUnit: profile.weightUnit, goal: profile.goal, goalWeight: profile.goalWeight)
        go(to: .goal)
    }

    // MARK: Goal + target weight

    func selectGoal(_ value: String) {
        form.selectGoal(value)
        if OnboardingOptions.weightGoals.contains(value) { openGoalWeight() }
    }

    func openGoalWeight() {
        goalWeightDraft = form.goalWeight
        goalWeightSaveError = nil
        showGoalWeight = true
    }

    /// The goal card's "Edit" link. Web bug, ported: it opens the sheet WITHOUT
    /// re-seeding the draft or clearing a stale error, so after Skip the old draft
    /// (and its old error) reappear.
    func editGoalWeight() {
        showGoalWeight = true
    }

    func saveGoalWeight() {
        if let conflict = OnboardingForm.goalWeightConflict(goal: form.goal, weight: form.weight,
                                                           goalWeight: goalWeightDraft, weightUnit: form.weightUnit) {
            goalWeightSaveError = conflict
            return
        }
        form.goalWeight = goalWeightDraft
        showGoalWeight = false
    }

    func skipGoalWeight() {
        form.goalWeight = ""
        showGoalWeight = false
    }

    // MARK: Finish

    private var profileInput: Components.Schemas.UserProfileInput {
        let f = form
        return .init(
            name: f.name.isEmpty ? nil : f.name,
            mode: f.mode,
            goal: f.goal,
            experience: f.experience,
            trainingDays: f.trainingDays,
            equipment: f.equipment,
            age: OnboardingForm.intOrNil(f.age),
            sex: f.sex.isEmpty ? nil : f.sex,
            weight: OnboardingForm.doubleOrNil(f.weight),
            weightUnit: f.weightUnit,
            goalWeight: OnboardingForm.doubleOrNil(f.goalWeight),
            activityLevel: f.activityLevel.isEmpty ? nil : f.activityLevel,
            preferredRestDays: f.preferredRestDays,
            injuries: f.injuries.isEmpty ? nil : f.injuries,
            injurySeverity: f.payloadInjurySeverity.flatMap(Components.Schemas.UserProfileInput.InjurySeverityPayload.init(rawValue:)),
            priorityMuscles: f.priorityMuscles,
            dailyCalorieTarget: OnboardingForm.intOrNil(f.dailyCalorieTarget),
            dailyStepTarget: OnboardingForm.intOrNil(f.dailyStepTarget),
            cardioDays: IndependentTargets.orderCardioDays(f.cardioDays),
            cardioMinutes: f.payloadCardioMinutes
        )
    }

    /// Saves the profile; AI + "Generate program" then builds the program here.
    /// Everything else (Independent, "Generate program later") lands on the app.
    func finish(generateNow: Bool) async {
        finishAction = generateNow ? .generate : .later
        createPending = true
        createError = false
        createErrorDetail = nil
        do {
            do {
                switch try await api.createProfile(body: .json(profileInput)) {
                case .created: break
                case .undocumented(let code, let payload):
                    throw await IntentAPIError.undocumented(statusCode: code, payload)
                }
            } catch where IntentAPIError.undecodableSuccessStatus(error) != nil {
                // The server saved the profile; only its reply didn't match the spec.
                // Retrying can't fix that, so carry on into the app.
                appLog.error("createProfile saved but reply didn't decode: \(String(describing: error), privacy: .public)")
            } catch {
                createError = true
                createErrorDetail = IntentAPIError.from(error).localizedDescription
                throw error
            }
            createPending = false
            if form.mode == "ai" && generateNow {
                phase = .generating
                let result = try await job.run(nil)
                setProgram(result)
                phase = .presentation
            } else {
                // The web toasts "Profile saved - generate any time from My Program"
                // for AI-later; the shell owns toasts here, so it just moves on.
                onFinished()
            }
        } catch {
            appLog.error("onboarding finish failed: \(String(describing: error), privacy: .public)")
            createPending = false
            phase = .form
            finishAction = nil
        }
    }

    func setProgram(_ result: Components.Schemas.Program) {
        program = result
        coreProgram = Self.convert(result)
    }

    /// API -> IntentCore through JSON (same field names on both sides).
    static func convert(_ program: Components.Schemas.Program) -> IntentCore.Program? {
        do {
            return try JSONDecoder().decode(IntentCore.Program.self, from: JSONEncoder().encode(program))
        } catch {
            appLog.error("onboarding program convert failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: Deck + commitment

    func regenerate(_ feedback: OnboardingFeedback) async {
        phase = .generating
        regenerateCount += 1
        updateError = false
        do {
            // The generator reads trainingDays from the profile, so a new count is saved first.
            if let days = feedback.trainingDays {
                do {
                    guard case .ok(let ok) = try await api.updateProfile(body: .json(.init(trainingDays: days))) else {
                        throw IntentAPIError.http(statusCode: 0, message: "updateProfile failed")
                    }
                    form.trainingDays = try ok.body.json.trainingDays
                } catch {
                    updateError = true
                    throw error
                }
            }
            let input = Components.Schemas.GenerateProgramInput(
                feedback: .init(categories: feedback.categories, note: feedback.note))
            setProgram(try await job.run(input))
        } catch {
            // Keep the previous program on screen; the deck's last page reports the error.
            appLog.error("onboarding regenerate failed: \(String(describing: error), privacy: .public)")
        }
        phase = .presentation
    }

    var deckError: Bool { job.isError || updateError }

    func commit(startDate: Date) async {
        guard let program else { return }
        commitPending = true
        defer { commitPending = false }
        do {
            // The API wants the local calendar day, never a UTC-midnight timestamp.
            let day = Calibration.localDateString(startDate)
            switch try await api.setProgramStartDate(path: .init(id: program.id), body: .json(.init(startDate: day))) {
            case .ok: break
            default: throw IntentAPIError.http(statusCode: 0, message: nil)
            }
        } catch {
            commitError = "Couldn't save your start date. Please try again."
            return
        }
        onFinished()
    }
}

/// What the "Tweak something" sheet sends back (SatisfactionGate's ProgramFeedback).
struct OnboardingFeedback {
    var categories: [Components.Schemas.ProgramFeedback.CategoriesPayloadPayload]
    var note: String
    /// Set only when "Training days" is picked; saved to the profile before regenerating.
    var trainingDays: Int?
}

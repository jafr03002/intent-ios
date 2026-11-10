import Foundation
import IntentCore

/// Check-in states the CI simulator screenshots (`-IntentScreen checkin-...`).
///
/// In mock mode every variant but `.none` reads its own fixture scenario
/// (`checkin`, or `checkin-locked`), so it renders the same in any run; `.none`
/// follows the run's `-IntentMockScenario`. `-CheckinStep <step>` (a `CheckinStep`
/// raw value, e.g. `offDay`) deep-links any variant into that step with sample answers.
enum CheckinDebug: Equatable {
    case none
    /// Step 2 (sleep), energy and sleep answered: a filled circle, Continue enabled.
    case step2
    /// The read-only sessions summary (3 of 4 logged).
    case sessions
    /// The missed-session question, an answer picked.
    case missed
    /// A free-text step with an answer typed.
    case text
    /// Answers filled in and submitted: the job runs and polls to the coach's message.
    case result
    /// The gate closed: the review was 3 days ago.
    case locked

    var pinnedScenario: String? {
        switch self {
        case .none: nil
        case .locked: "checkin-locked"
        default: "checkin"
        }
    }

    private var targetStep: CheckinStep? {
        if let flag = ProcessInfo.processInfo.arguments.firstIndex(of: "-CheckinStep"),
           ProcessInfo.processInfo.arguments.indices.contains(flag + 1),
           let step = CheckinStep(rawValue: ProcessInfo.processInfo.arguments[flag + 1]) {
            return step
        }
        switch self {
        case .step2: return .sleep
        case .sessions: return .sessions
        case .missed: return .missedReason
        case .text: return .exerciseIssues
        case .none, .result, .locked: return nil
        }
    }

    /// Alex's week, as a client would answer it.
    static var sampleAnswers: CheckinAnswers {
        var a = CheckinAnswers()
        a.energy = 4
        a.sleep = 3
        a.sleepDecline = "Two late nights for work."
        a.soreness = "moderate"
        a.missedReason = "forgot_to_log"
        a.exerciseIssues = "Left shoulder pinches a little at the bottom of the incline press."
        a.hungerAppetite = 4
        a.offDayDeviation = false
        a.wentWell = "Bench moved up again and Upper B felt strong."
        a.didntGoWell = "Late nights midweek."
        return a
    }

    @MainActor
    func apply(to model: CheckinModel) async {
        if self == .step2 {
            model.answers.energy = 4
            model.answers.sleep = 4
        } else if let step = targetStep {
            model.answers = Self.sampleAnswers
            model.step = model.steps.firstIndex(of: step) ?? 0
        }
        if self == .step2, let step = targetStep {
            model.step = model.steps.firstIndex(of: step) ?? 0
        }
        if self == .result {
            model.answers = Self.sampleAnswers
            model.step = model.steps.count - 1
            await model.submit()
        }
    }
}

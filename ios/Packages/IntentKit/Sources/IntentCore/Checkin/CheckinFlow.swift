import Foundation

// Port of the pure parts of pages/checkin.tsx (the weekly check-in form), the
// dashboard's showCheckinBanner rule (pages/dashboard.tsx) and the polling policy
// of hooks/useAiJob.ts. The check-in gate itself is `Calibration.checkinGate`.
//
// One question per screen, as in onboarding: 12 steps on a full week, 13 when the
// client logged fewer sessions than planned (the missed-session step).

public enum CheckinStep: String, CaseIterable, Sendable {
    case energy, sleep, sleepDecline, soreness, sessions, missedReason, exerciseIssues
    case hunger, offDay, digestion, wentWell, didntGoWell, notes
}

/// A missed-session answer (`CheckinInput.missedSessionReason`).
public struct CheckinMissedReason: Sendable, Equatable {
    public let value: String
    public let label: String
}

/// Everything the form collects. Zero / empty / nil mean "not answered", as on the web.
public struct CheckinAnswers: Sendable, Equatable {
    public var energy = 0
    public var sleep = 0
    public var sleepDecline = ""
    public var soreness = ""
    public var missedReason = ""
    public var exerciseIssues = ""
    public var hungerAppetite = 0
    public var offDayDeviation: Bool?
    public var digestionIssues = ""
    public var wentWell = ""
    public var didntGoWell = ""
    public var notes = ""

    public init() {}
}

public enum CheckinFlow {
    public static let energyLabels = ["Drained", "Low", "OK", "Good", "Great"]
    public static let sleepLabels = ["Terrible", "Poor", "OK", "Good", "Great"]
    public static let hungerLabels = ["None", "Low", "Normal", "High", "Ravenous"]
    /// Shown capitalised, stored lower-cased.
    public static let sorenessOptions = ["Low", "Moderate", "High"]

    public static let missedReasons: [CheckinMissedReason] = [
        .init(value: "forgot_to_log", label: "I trained it, I just forgot to log it"),
        .init(value: "time", label: "Skipped - time or life got in the way"),
        .init(value: "fatigue", label: "Skipped - felt too beat up"),
        .init(value: "injury", label: "Skipped - injury or pain"),
        .init(value: "other", label: "Skipped - something else"),
    ]

    /// `stepsFor(adherence)`: the missed-session step only exists when the client came
    /// up short. Pass nil while adherence is loading or unavailable (404 before an AI
    /// program exists).
    public static func steps(loggedSessions: Int?, plannedSessions: Int?) -> [CheckinStep] {
        var steps: [CheckinStep] = [.energy, .sleep, .sleepDecline, .soreness, .sessions]
        if let logged = loggedSessions, let planned = plannedSessions, logged < planned {
            steps.append(.missedReason)
        }
        steps += [.exerciseIssues, .hunger, .offDay, .digestion, .wentWell, .didntGoWell, .notes]
        return steps
    }

    /// The adherence answer arriving can add or drop a step: clamp rather than point
    /// past the end of a now-shorter flow.
    public static func clampedStep(_ step: Int, count: Int) -> Int {
        min(step, count - 1)
    }

    /// Whether Continue is enabled. Free-text steps (and the read-only sessions step)
    /// can always be skipped.
    public static func canAdvance(_ step: CheckinStep, _ a: CheckinAnswers) -> Bool {
        switch step {
        case .energy: a.energy > 0
        case .sleep: a.sleep > 0
        case .soreness: !a.soreness.isEmpty
        case .missedReason: !a.missedReason.isEmpty
        case .hunger: a.hungerAppetite > 0
        case .offDay: a.offDayDeviation != nil
        default: true
        }
    }

    /// The missed-session question names the day when only one is missing.
    public static func missedReasonTitle(missingDayLabels: [String]) -> String {
        missingDayLabels.count == 1
            ? "What happened with \(missingDayLabels[0])?"
            : "What happened with the sessions you didn't log?"
    }

    /// "Plus N extra session(s) beyond your program days." (nil when there are none).
    public static func extraSessionsLine(_ extra: Int) -> String? {
        extra > 0 ? "Plus \(extra) extra session\(extra == 1 ? "" : "s") beyond your program days." : nil
    }

    /// `value || null` for the optional text answers.
    public static func nullIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}

// MARK: - Dashboard banner

/// The dashboard's "Time for your weekly check-in" banner (dashboard.tsx
/// `showCheckinBanner`): AI mode only, an AI program must exist, closed during
/// calibration and until a week after the review; otherwise 6 days after training
/// started (first ever) or 7 days after the last check-in.
public enum CheckinBanner {
    public static func shouldShow(
        isIndependent: Bool,
        isLoading: Bool,
        hasCurrentProgram: Bool,
        programs: [PhaseRow],
        latestCheckinAt: String?,
        onboardingCompletedAt: String?,
        now: Date = Date(),
        timeZone tz: TimeZone = .current
    ) -> Bool {
        if isIndependent { return false }
        if isLoading { return false }
        if !hasCurrentProgram { return false }
        let gate = Calibration.checkinGate(programs, latestCheckinAt: latestCheckinAt, now: now, timeZone: tz)
        guard case .open(let firstAfterReview) = gate else { return false }
        if firstAfterReview { return true }
        guard let latest = latestCheckinAt else {
            guard let start = Calibration.trainingStart(programs, onboardingCompletedAt: onboardingCompletedAt, timeZone: tz)
            else { return false }
            return daysSince(JSDate.ms(start), now: now) >= 6
        }
        return daysSince(JSDate.parse(latest, tz), now: now) >= 7
    }

    /// `Math.floor((now - then) / day)`; an unparseable date (NaN) compares false.
    static func daysSince(_ thenMs: Double, now: Date) -> Double {
        ((JSDate.ms(now) - thenMs) / JSDate.msPerDay).rounded(.down)
    }
}

// MARK: - AI job polling

/// `useAiJob`'s timing: poll every 2.5 s, and give up on a job (or a stored job id)
/// 6.5 minutes after it started - the server fails jobs after six.
public enum AiJobPolicy {
    public static let pollInterval: Duration = .milliseconds(2500)
    public static let giveUpAfter: TimeInterval = 6.5 * 60

    /// A stored job id from an earlier visit is worth resuming.
    public static func isResumable(startedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(startedAt) < giveUpAfter
    }

    /// The poll loop has lost the server rather than the job.
    public static func hasGivenUp(startedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(startedAt) > giveUpAfter
    }

    public static let checkinFailureMessage = "Your check-in could not be processed. Please try again."
}

import Foundation

// The pure core of hooks/usePrDetection.ts. The toast list and its 4-second
// timeout are UI; what's here is the baseline and the judgement.

/// The numbers of a set being judged (the logger's current values).
public struct SetNumbers: Sendable, Equatable, Codable {
    public var weight: Double
    public var reps: Int
    public var repsLeft: Int
    public var repsRight: Int
    public init(weight: Double, reps: Int = 0, repsLeft: Int = 0, repsRight: Int = 0) {
        self.weight = weight; self.reps = reps; self.repsLeft = repsLeft; self.repsRight = repsRight
    }
    public init(_ set: DraftSet) {
        self.init(weight: set.weight, reps: set.reps, repsLeft: set.repsLeft, repsRight: set.repsRight)
    }
}

public struct PrJudgement: Sendable, Equatable {
    /// Whether the set is a new PR (store it on the set as `isNewPr`).
    public var isNewPr: Bool
    /// Whether to raise the PR toast: a new PR that wasn't already flagged.
    public var shouldFlash: Bool
}

/// Judges each completed set against the prior best e1RM for that exercise.
///
/// The baseline is saved history (previous sessions only) plus the server's PRs. A
/// set can only be a PR if it beats a set from an earlier session, so the first
/// sets ever logged for an exercise are a baseline, never a record. Value type: the
/// session-best memory lives in the struct, so keep one per open session.
public struct PrDetector: Sendable, Equatable {
    /// Prior all-time best e1RM per lowercased exercise name.
    public private(set) var baseline: [String: Double]
    /// Exercises that have ever been logged (or hold a server PR).
    public private(set) var priorLogged: Set<String>
    /// Best PR score set during this session, per exercise.
    public private(set) var sessionBest: [String: Double] = [:]

    public init(history: [WorkoutLog]?, personalRecords: [PersonalRecord]?) {
        var best: [String: Double] = [:]
        var seen = Set<String>()
        for log in history ?? [] {
            for ex in log.exercisesLogged {
                let key = JS.lower(ex.name)
                if key.isEmpty { continue }
                for s in ex.sets {
                    if SessionLogs.isEmptySet(s) { continue }
                    seen.insert(key)
                    // History reads a set as unilateral when it carries L/R reps,
                    // whatever the exercise's current flag says.
                    let reps = s.repsLeft != nil || s.repsRight != nil
                        ? min(s.repsLeft ?? 0, s.repsRight ?? 0)
                        : (s.reps ?? 0)
                    let score = SessionLogs.estimatedOneRepMax(weight: s.weight, reps: Double(reps))
                    if score > (best[key] ?? 0) { best[key] = score }
                }
            }
        }
        // Server PRs can reach back past history's window; fold them in so the
        // baseline never regresses for very active users.
        for pr in personalRecords ?? [] {
            let key = JS.lower(pr.exercise)
            seen.insert(key)
            let score = SessionLogs.estimatedOneRepMax(weight: pr.maxWeight, reps: Double(pr.reps ?? 0))
            if score > (best[key] ?? 0) { best[key] = score }
        }
        baseline = best
        priorLogged = seen
    }

    /// New history/PRs arrived (the web hook's effect re-running): rebuild the
    /// baseline but keep this session's bests, as the hook's refs do.
    public mutating func updateBaseline(history: [WorkoutLog]?, personalRecords: [PersonalRecord]?) {
        let fresh = PrDetector(history: history, personalRecords: personalRecords)
        baseline = fresh.baseline
        priorLogged = fresh.priorLogged
    }

    /// Judge a just-completed set. `wasPr` is whether that same set was already
    /// flagged, so re-typing a PR set doesn't flash again. Only a flashing PR raises
    /// the session best (as on the web).
    public mutating func judgeSet(name: String, isUnilateral: Bool, set: SetNumbers, wasPr: Bool) -> PrJudgement {
        let key = JS.lower(name)
        let reps = isUnilateral ? min(set.repsLeft, set.repsRight) : set.reps
        let score = SessionLogs.estimatedOneRepMax(weight: set.weight, reps: Double(reps))
        let currentBest = max(baseline[key] ?? 0, sessionBest[key] ?? 0)
        let isNewPr = priorLogged.contains(key) && score > currentBest
        let flash = isNewPr && !wasPr
        if flash { sessionBest[key] = score }
        return PrJudgement(isNewPr: isNewPr, shouldFlash: flash)
    }
}

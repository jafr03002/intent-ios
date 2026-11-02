import Foundation

// Port of lib/trainingTargets.ts: per-set targets for the AI-mode logger - what to
// try to beat this session, from what was lifted last time. Pure arithmetic.
//
// Double progression, the per-set view of progressive overload: add a rep until
// the rep cap, then add load (~2.5%, snapped to a real plate step) and drop back
// to the bottom of the prescribed range.

public enum ExerciseClass: String, Sendable, Codable, CaseIterable {
    case isolation, compound
}

public struct SetTarget: Sendable, Equatable, Codable {
    public enum Change: String, Sendable, Codable { case rep, weight }
    public var weight: Double
    public var reps: Int
    /// What moved since last time.
    public var change: Change
    /// "+1 rep" or "+2.5 kg".
    public var delta: String
}

public enum TrainingTargets {
    /// Decided by name keyword (the AI writes names freely); anything not
    /// recognisably single-joint is compound.
    static let isolationKeywords = [
        "curl", "raise", "fly", "flies", "flye", "pec dec", "extension", "pushdown", "skullcrusher", "kickback",
        "crunch", "calf", "toe press", "abduction", "adductor", "shrug", "face pull", "pullover", "pallof",
        "plank", "wrist",
    ]

    public static func classifyExercise(_ name: String) -> ExerciseClass {
        let lower = JS.lower(name)
        return isolationKeywords.contains { lower.contains($0) } ? .isolation : .compound
    }

    /// Jakob's rule: X = last session's reps + 1, while X stays inside the cap.
    public static func repCap(_ cls: ExerciseClass) -> Int { cls == .isolation ? 12 : 9 }

    static let loadFraction = 0.025

    static func weightStep(_ weight: Double, _ cls: ExerciseClass, unit: String) -> Double {
        let pounds = unit == "lb" || unit == "lbs"
        let steps: [Double] = switch (pounds, cls) {
        case (false, .isolation): [1.25, 2.5]
        case (false, .compound): [1.25, 2.5, 5]
        case (true, .isolation): [2.5, 5]
        case (true, .compound): [2.5, 5, 10]
        }
        let ideal = weight * loadFraction
        return steps.reduce(steps[0]) { best, s in Swift.abs(s - ideal) < Swift.abs(best - ideal) ? s : best }
    }

    /// The bottom of a prescribed rep range - "8-12", "8–12", "8 to 12", "10". Nil
    /// with no number to read ("AMRAP") or when it reads as 0.
    public static func repRangeFloor(_ reps: String?) -> Int? {
        var digits = ""
        for c in reps ?? "" {
            if let a = c.asciiValue, a >= 48, a <= 57 {
                digits.append(c)
            } else if !digits.isEmpty {
                break
            }
        }
        guard !digits.isEmpty else { return nil }
        let n = Double(digits) ?? 0
        guard n.isFinite, n > 0 else { return nil }
        return n > Double(Int.max) ? Int.max : Int(n)
    }

    /// The target for one set from the matching set last session; nil when there is
    /// nothing to progress from (no reps). A bodyweight set (weight 0) only ever
    /// progresses on reps.
    public static func computeSetTarget(name: String, lastWeight: Double, lastReps: Int, targetReps: String?,
                                        weightUnit: String) -> SetTarget? {
        guard lastReps > 0 else { return nil }
        let cls = classifyExercise(name)
        let next = lastReps + 1
        if next <= repCap(cls) || !(lastWeight > 0) {
            return SetTarget(weight: lastWeight, reps: next, change: .rep, delta: "+1 rep")
        }
        let step = weightStep(lastWeight, cls, unit: weightUnit)
        // Round away float noise, keeping quarter-kilo steps.
        let weight = JS.round((lastWeight + step) * 100) / 100
        // A floor at or above last time's reps can't be a reset.
        let floor = repRangeFloor(targetReps)
        let reps = floor.map { $0 < lastReps ? $0 : lastReps } ?? lastReps
        return SetTarget(weight: weight, reps: reps, change: .weight, delta: "+\(JS.string(step)) \(weightUnit)")
    }

    /// Target from a historic set. Unilateral sets progress on the weaker side.
    public static func targetFromPreviousSet(_ prev: LoggedSet?, name: String, targetReps: String?,
                                             weightUnit: String) -> SetTarget? {
        guard let prev else { return nil }
        let reps = prev.repsLeft != nil || prev.repsRight != nil
            ? min(prev.repsLeft ?? 0, prev.repsRight ?? 0)
            : (prev.reps ?? 0)
        return computeSetTarget(name: name, lastWeight: prev.weight, lastReps: reps, targetReps: targetReps, weightUnit: weightUnit)
    }
}

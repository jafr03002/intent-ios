import Foundation

// Port of lib/independentTargets.ts. Independent mode has no AI phase, so its
// dashboard "phase" comes straight from the profile goal:
//   gain_weight -> bulk, general (and anything else) -> maintenance, lose_weight -> diet.

public enum IndependentPhase: String, Sendable, Codable, CaseIterable {
    case bulk, maintenance, diet

    /// The matching short-term phase, for colours.
    public var shortTermPhase: ShortTermPhase {
        switch self {
        case .bulk: .bulk
        case .maintenance: .maintenance
        case .diet: .diet
        }
    }
}

public struct PhaseOption: Sendable, Equatable {
    public var phase: IndependentPhase
    /// The profile goal slug it maps to.
    public var goal: String
    /// What the user is doing, in plain words.
    public var heading: String
    /// The training-world name for it.
    public var tag: String
    public var sub: String
}

public enum IndependentTargets {
    public static let phaseOptions: [PhaseOption] = [
        PhaseOption(phase: .bulk, goal: "gain_weight", heading: "Gaining weight", tag: "Bulk phase", sub: "Build muscle in a surplus"),
        PhaseOption(phase: .maintenance, goal: "general", heading: "General fitness", tag: "Maintenance", sub: "Hold weight, stay consistent"),
        PhaseOption(phase: .diet, goal: "lose_weight", heading: "Losing weight", tag: "Diet phase", sub: "Lean out, keep muscle"),
    ]

    public static func goalToPhase(_ goal: String?) -> IndependentPhase {
        switch goal {
        case "gain_weight": .bulk
        case "lose_weight": .diet
        default: .maintenance
        }
    }

    public static func phaseOption(_ phase: IndependentPhase) -> PhaseOption {
        phaseOptions.first { $0.phase == phase }!
    }

    /// The goal-weight message for a phase, or nil. Bulk/diet need a target pointing
    /// the right way from the current weight (checked only when it's known);
    /// maintenance has none. Range is checked before direction.
    public static func phaseGoalWeightError(phase: IndependentPhase, currentWeight: Double?, goalWeight: String,
                                            unit: String) -> String? {
        if phase == .maintenance { return nil }
        if JS.trim(goalWeight).isEmpty { return "Set a goal weight to continue." }
        let target = JS.parseFloat(goalWeight)
        if !target.isFinite { return "Enter a valid goal weight." }
        if let outOfRange = FieldLimits.rangeError(goalWeight, FieldLimits.goalWeight) { return outOfRange }
        guard let current = currentWeight, current.isFinite else { return nil }
        let c = JS.string(current), t = JS.string(target)
        if target == current {
            return "That's your current weight (\(c) \(unit)) - enter a target \(phase == .bulk ? "above" : "below") it."
        }
        if phase == .bulk && target < current {
            return "Bulk needs a target above your current \(c) \(unit). \(t) \(unit) is below it - that's a diet."
        }
        if phase == .diet && target > current {
            return "Diet needs a target below your current \(c) \(unit). \(t) \(unit) is above it - that's a bulk."
        }
        return nil
    }

    /// Weekday labels used by the cardio picker, stored verbatim in cardioDays.
    public static let cardioDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Stored day labels back in week order (unknown labels and duplicates drop out).
    public static func orderCardioDays(_ days: [String]) -> [String] {
        cardioDays.filter(days.contains)
    }
}

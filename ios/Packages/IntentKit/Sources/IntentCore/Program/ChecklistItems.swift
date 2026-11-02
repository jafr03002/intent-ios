import Foundation

// Port of lib/checklistItems.ts: the non-weight half of a program day ("5 min
// stretching", "2 min plank"). A checklist item is an Exercise with kind
// .checklist; `sets` is its round count. The invariant that matters: a logged
// checklist item carries NO weight and NO reps, which keeps it out of the
// volume/e1RM/PR maths. Never synthesise a fake set to represent a tick.

/// A semantic colour slot for the design module to resolve. The web uses the
/// theme's chart tokens (`hsl(var(--chart-N))`).
public enum ChartToken: String, Sendable, CaseIterable, Codable {
    case chart1, chart2, chart3, chart4, chart5

    /// The web's CSS spelling, e.g. "hsl(var(--chart-4))".
    public var css: String { "hsl(var(--chart-\(rawValue.dropFirst(5))))" }
}

public struct ChecklistCategoryMeta: Sendable, Equatable {
    public var value: ChecklistCategory
    public var label: String
    public var token: ChartToken
}

public struct TargetTypeOption: Sendable, Equatable {
    public var value: TargetType
    public var label: String
}

/// The shape describeTarget reads - a program Exercise or a logger row.
public struct ChecklistTarget: Sendable, Equatable {
    public var targetType: TargetType?
    public var targetSeconds: Int?
    public var targetValue: Double?
    public var targetUnit: String?
    public var rounds: Int?

    public init(targetType: TargetType? = nil, targetSeconds: Int? = nil, targetValue: Double? = nil,
                targetUnit: String? = nil, rounds: Int? = nil) {
        self.targetType = targetType; self.targetSeconds = targetSeconds; self.targetValue = targetValue
        self.targetUnit = targetUnit; self.rounds = rounds
    }

    public init(_ ex: Exercise) {
        self.init(targetType: ex.targetType, targetSeconds: ex.targetSeconds, targetValue: ex.targetValue,
                  targetUnit: ex.targetUnit, rounds: ex.sets)
    }

    /// The logger card's target (no rounds - the web passes the row itself, which
    /// has no `rounds` field).
    public init(_ ex: DraftExercise) {
        self.init(targetType: ex.targetType, targetSeconds: ex.targetSeconds, targetValue: ex.targetValue,
                  targetUnit: ex.targetUnit)
    }
}

public enum ChecklistItems {
    public static let categories: [ChecklistCategoryMeta] = [
        .init(value: .stretch, label: "Stretch", token: .chart4),
        .init(value: .mobility, label: "Mobility", token: .chart4),
        .init(value: .core, label: "Core", token: .chart2),
        .init(value: .breathing, label: "Breathing", token: .chart1),
        .init(value: .other, label: "Other", token: .chart4),
    ]

    /// Fallback accent for an item with no category.
    public static let accent: ChartToken = .chart4

    public static let targetTypeOptions: [TargetTypeOption] = [
        .init(value: .none, label: "Just tick it"),
        .init(value: .duration, label: "Duration"),
        .init(value: .count, label: "Reps / count"),
        .init(value: .distance, label: "Distance"),
    ]

    public static let distanceUnits = ["m", "km"]

    /// What the duration wheel can express: 60 minutes plus 59 seconds.
    public static let maxWheelMinutes = 60
    public static let maxWheelSeconds = maxWheelMinutes * 60 + 59

    public static func categoryMeta(_ category: String?) -> ChecklistCategoryMeta? {
        categories.first { $0.value.rawValue == category }
    }

    public static func categoryMeta(_ category: ChecklistCategory?) -> ChecklistCategoryMeta? {
        categoryMeta(category?.rawValue)
    }

    /// Narrows a free-form stored value to a known category, or nil.
    public static func parseCategory(_ value: String?) -> ChecklistCategory? {
        categoryMeta(value)?.value
    }

    /// Seconds -> "m:ss" (or "h:mm:ss" past an hour).
    public static func formatDuration(_ totalSeconds: Double) -> String {
        let s = totalSeconds.isFinite ? Int(Swift.max(0, totalSeconds.rounded(.down))) : 0
        let hours = s / 3600, minutes = (s % 3600) / 60, seconds = s % 60
        if hours > 0 { return "\(hours):\(SessionDuration.pad2(minutes)):\(SessionDuration.pad2(seconds))" }
        return "\(minutes):\(SessionDuration.pad2(seconds))"
    }

    /// "2:30", "× 20", "400 m", or nil for a plain tick-off.
    public static func describeTarget(_ item: ChecklistTarget) -> String? {
        switch item.targetType {
        case .duration:
            guard let secs = item.targetSeconds, secs > 0 else { return nil }
            return formatDuration(Double(secs))
        case .count:
            return item.targetValue.map { "× \(JS.string($0))" }
        case .distance:
            return item.targetValue.map { "\(JS.string($0)) \(item.targetUnit ?? "m")" }
        default:
            return nil
        }
    }

    /// "2 × 2:30" with more than one round, else just the target ("3 rounds" when
    /// there's no target).
    public static func describeTargetWithRounds(_ item: ChecklistTarget) -> String? {
        let target = describeTarget(item)
        let rounds = item.rounds ?? 1
        guard let target else { return rounds > 1 ? "\(rounds) rounds" : nil }
        return rounds > 1 ? "\(rounds) × \(target)" : target
    }

    /// Clamps a count/distance amount to the band openapi.yaml accepts.
    public static func clampTargetValue(_ value: Double, targetType: TargetType) -> Double {
        if !value.isFinite || value < 0 { return 0 }
        let maxValue = targetType == .count ? FieldLimits.loggedSetReps.max : 100_000
        return Swift.min(value, maxValue)
    }
}

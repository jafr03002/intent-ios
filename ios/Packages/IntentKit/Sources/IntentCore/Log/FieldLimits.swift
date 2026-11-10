import Foundation

// Port of lib/fieldLimits.ts: the plausibility bands the API enforces, restated for
// inline validation. MUST stay in step with the min/max on openapi.yaml's input
// schemas. None of these are coaching opinions.

public struct FieldLimit: Sendable, Equatable {
    public enum Article: String, Sendable { case a, an }
    public var min: Double
    public var max: Double
    /// Singular noun phrase that reads inside "Enter a ___ between X and Y".
    public var noun: String
    public var article: Article
    /// Follows the numbers in the message, e.g. "kcal".
    public var unit: String?
    /// Whole numbers only.
    public var integer: Bool

    public init(min: Double, max: Double, noun: String, article: Article, unit: String? = nil, integer: Bool = false) {
        self.min = min; self.max = max; self.noun = noun; self.article = article; self.unit = unit; self.integer = integer
    }
}

public struct Bounds: Sendable, Equatable {
    public var min: Double
    public var max: Double
    public init(min: Double, max: Double) { self.min = min; self.max = max }
}

public enum FieldLimits {
    public static let age = FieldLimit(min: 13, max: 120, noun: "age", article: .an, integer: true)
    /// Unit-agnostic: the same band covers 20 kg and 1000 lbs.
    public static let weight = FieldLimit(min: 20, max: 1000, noun: "weight", article: .a)
    public static let goalWeight = FieldLimit(min: 20, max: 1000, noun: "goal weight", article: .a)
    public static let dailyCalorieTarget = FieldLimit(min: 800, max: 10000, noun: "calorie target", article: .a, unit: "kcal", integer: true)
    public static let dailyStepTarget = FieldLimit(min: 0, max: 100_000, noun: "step target", article: .a, unit: "steps", integer: true)
    public static let cardioMinutes = FieldLimit(min: 0, max: 1440, noun: "cardio duration", article: .a, unit: "minutes", integer: true)
    public static let calories = FieldLimit(min: 0, max: 20000, noun: "calorie count", article: .a, unit: "kcal", integer: true)
    public static let steps = FieldLimit(min: 0, max: 200_000, noun: "step count", article: .a, unit: "steps", integer: true)
    public static let sets = FieldLimit(min: 1, max: 50, noun: "set count", article: .a, integer: true)

    /// All of the above by their web key, for table-driven callers.
    public static let all: [String: FieldLimit] = [
        "age": age, "weight": weight, "goalWeight": goalWeight, "dailyCalorieTarget": dailyCalorieTarget,
        "dailyStepTarget": dailyStepTarget, "cardioMinutes": cardioMinutes, "calories": calories,
        "steps": steps, "sets": sets,
    ]

    /// Bounds for a logged set - clamped at the input rather than reported.
    public static let loggedSetWeight = Bounds(min: 0, max: 2000)
    public static let loggedSetReps = Bounds(min: 0, max: 1000)

    public static let maxExerciseName = 80
    public static let maxDayLabel = 60
    public static let maxProfileName = 80

    public static func clampToBounds(_ value: Double, _ bounds: Bounds) -> Double {
        guard value.isFinite else { return bounds.min }
        return Swift.min(Swift.max(value, bounds.min), bounds.max)
    }

    /// The message to show under the field, or nil. Blank input is always fine.
    /// `raw` is parsed with JS `Number()` semantics ("1e3" and "0x10" are numbers,
    /// "80kg" is not).
    public static func rangeError(_ raw: String, _ limit: FieldLimit) -> String? {
        let trimmed = JS.trim(raw)
        if trimmed.isEmpty { return nil }
        let value = JS.number(trimmed)
        if !value.isFinite { return "Enter a valid \(limit.noun)." }
        if limit.integer && value != value.rounded(.towardZero) {
            return "Enter your \(limit.noun) as a whole number."
        }
        if value < limit.min || value > limit.max {
            let suffix = limit.unit.map { " \($0)" } ?? ""
            return "Enter \(limit.article.rawValue) \(limit.noun) between \(JS.groupedEnUS(limit.min)) and \(JS.groupedEnUS(limit.max))\(suffix)."
        }
        return nil
    }

    /// True when every value is blank or in range.
    public static func allInRange(_ pairs: [(String, FieldLimit)]) -> Bool {
        pairs.allSatisfy { rangeError($0.0, $0.1) == nil }
    }
}

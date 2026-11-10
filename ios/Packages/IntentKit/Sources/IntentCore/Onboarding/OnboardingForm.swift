import Foundation

// Port of the pure parts of pages/onboarding.tsx: the option lists, the step
// sequence per mode, the form state with its toggle rules and validation, the
// calorie suggestion, the review rows and the createProfile payload values.

public enum OnboardingStep: String, Sendable, CaseIterable, Equatable {
    case mode, name, bodyStats, goal
    case experience, activity, trainingDays, preferredRestDays, equipment, details, priorityMuscles
    case targets, review
}

/// One stacked choice: the stored slug, its label and the sub line under it.
public struct OnboardingChoice: Sendable, Equatable {
    public var value: String
    public var label: String
    public var sub: String
    public init(_ value: String, _ label: String, _ sub: String) { self.value = value; self.label = label; self.sub = sub }
}

public enum OnboardingOptions {
    public static let modes: [OnboardingChoice] = [
        .init("ai", "AI Coach", "AI builds your program, monitors progress, and adjusts weekly based on your check-ins"),
        .init("independent", "Independent", "You're in control. Build your own program, log your sessions, and track progression yourself - no AI involved"),
    ]

    public static let goals: [OnboardingChoice] = [
        .init("gain_weight", "Gain weight", "Build muscle in a surplus"),
        .init("lose_weight", "Lose weight", "Lean out while keeping muscle"),
        .init("general", "General fitness", "Overall health & consistency"),
    ]

    /// Goals that ask for a long-term target weight (via a sheet on selection).
    public static let weightGoals: Set<String> = ["gain_weight", "lose_weight"]

    /// Older profiles stored these slugs; aliased so review lookups still resolve.
    public static let legacyGoalLabels: [String: String] = [
        "hypertrophy": "Build muscle",
        "strength": "Get stronger",
        "fat_loss": "Lose fat & get lean",
    ]

    public static func goalLabel(_ value: String) -> String? {
        goals.first { $0.value == value }?.label ?? legacyGoalLabels[value]
    }

    public static let activity: [OnboardingChoice] = [
        .init("low", "Low", "Fewer than 6,000 steps a day"),
        .init("moderate", "Moderate", "6,000 – 9,999 steps a day"),
        .init("high", "High", "10,000 – 12,500+ steps a day"),
    ]

    /// Rest-day choices (no sub line).
    public static let weekdays: [OnboardingChoice] = [
        .init("mon", "Mon", ""), .init("tue", "Tue", ""), .init("wed", "Wed", ""), .init("thu", "Thu", ""),
        .init("fri", "Fri", ""), .init("sat", "Sat", ""), .init("sun", "Sun", ""),
    ]

    public static let injurySeverity: [OnboardingChoice] = [
        .init("low", "Low", "Mild discomfort - doesn't stop you training as normal"),
        .init("medium", "Medium", "Noticeable pain - some movements need to be avoided or modified"),
        .init("high", "High", "Significant pain or limitation - needs major changes, possibly medical clearance"),
    ]

    public static let experience: [OnboardingChoice] = [
        .init("beginner", "Beginner", "Under 1 year or returning after a long break"),
        .init("intermediate", "Intermediate", "1–3 years consistent training"),
        .init("advanced", "Advanced", "3+ years consistent training"),
    ]

    public static let equipment = [
        "Full gym", "Dumbbells only", "Barbell & rack", "Cable machines",
        "Smith machine", "Resistance bands", "Pull-up bar", "Home gym", "No equipment",
    ]

    public static let noPreference = "No preference"
    public static let muscles: [String] = Muscle.allCases.map(\.label) + [noPreference]

    public static let trainingDayRange = 2...6

    /// Everyone gets mode + the basics + goal; the rest is AI-coaching input, so
    /// Independent goes from the goal to its own targets step and the review.
    public static func steps(for mode: String) -> [OnboardingStep] {
        let base: [OnboardingStep] = [.mode, .name, .bodyStats, .goal]
        if mode == "ai" {
            return base + [.experience, .activity, .trainingDays, .preferredRestDays, .equipment, .details, .priorityMuscles, .review]
        }
        return base + [.targets, .review]
    }

    public static let suggestedCaloriesMin = 1200.0
    public static let suggestedCaloriesMax = 5000.0

    /// Maintenance ~= 30 kcal/kg nudged for the goal, rounded to 50 and clamped.
    /// An unparseable weight counts as 75 kg.
    public static func suggestCalories(weight: String, weightUnit: String, goal: String) -> Int {
        let w = JS.parseFloat(weight)
        let kg = w.isFinite ? (weightUnit == "lbs" ? w / 2.2046 : w) : 75
        var cals = kg * 30
        if goal == "lose_weight" { cals -= 400 } else if goal == "gain_weight" { cals += 300 }
        let rounded = JS.round(cals / 50) * 50
        return Int(Swift.min(Swift.max(rounded, suggestedCaloriesMin), suggestedCaloriesMax))
    }
}

/// The onboarding form, field for field as the web's `FormState` (strings for
/// what the user types, so half-typed values survive).
public struct OnboardingForm: Sendable, Equatable {
    public var mode = ""
    public var name = ""
    public var goal = ""
    public var goalWeight = ""
    public var experience = ""
    public var activityLevel = ""
    public var trainingDays = 4
    public var preferredRestDays: [String] = []
    public var equipment: [String] = []
    public var age = ""
    public var sex = ""
    public var weight = ""
    public var weightUnit = "kg"
    public var injuries = ""
    public var injurySeverity = ""
    public var priorityMuscles: [String] = []
    public var dailyCalorieTarget = ""
    public var dailyStepTarget = ""
    public var cardioDays: [String] = []
    public var cardioMinutes = ""

    public init() {}

    /// An AI-mode profile missing goal or experience never finished AI setup (it
    /// came through Independent, or an earlier attempt broke off): true when the
    /// flow should prefill the basics and resume at the goal step.
    public static func shouldResume(mode: String, goal: String, experience: String) -> Bool {
        mode == "ai" && (goal.isEmpty || experience.isEmpty)
    }

    /// Prefill from the saved profile, numbers as JS's `String(n)` writes them.
    public mutating func resume(name: String?, age: Int?, sex: String?, weight: Double?, weightUnit: String?,
                                goal: String, goalWeight: Double?) {
        mode = "ai"
        self.name = name ?? ""
        self.age = age.map(String.init) ?? ""
        self.sex = sex ?? ""
        self.weight = weight.map { JS.string($0) } ?? ""
        self.weightUnit = weightUnit ?? "kg"
        self.goal = goal
        self.goalWeight = goalWeight.map { JS.string($0) } ?? ""
    }

    // MARK: Validation

    /// A target pointing the opposite way to the goal is a typo. Range first, then
    /// direction; nil when there's no weight goal or either weight is blank.
    public static func goalWeightConflict(goal: String, weight: String, goalWeight: String, weightUnit: String) -> String? {
        guard OnboardingOptions.weightGoals.contains(goal) else { return nil }
        if let outOfRange = FieldLimits.rangeError(goalWeight, FieldLimits.goalWeight) { return outOfRange }
        let current = JS.parseFloat(weight)
        let target = JS.parseFloat(goalWeight)
        guard current.isFinite, target.isFinite else { return nil }
        let c = JS.string(current), t = JS.string(target), unit = weightUnit
        if target == current {
            let direction = goal == "gain_weight" ? "above" : "below"
            return "That's your current weight (\(c) \(unit)), so there's nothing to reach. Enter a target \(direction) it, or pick General fitness instead."
        }
        if goal == "gain_weight" && target < current {
            return "You picked Gain weight, but \(t) \(unit) is below your current \(c) \(unit) - that's losing weight. Enter a target above \(c) \(unit), or switch your goal to Lose weight."
        }
        if goal == "lose_weight" && target > current {
            return "You picked Lose weight, but \(t) \(unit) is above your current \(c) \(unit) - that's gaining weight. Enter a target below \(c) \(unit), or switch your goal to Gain weight."
        }
        return nil
    }

    public var goalWeightError: String? {
        Self.goalWeightConflict(goal: goal, weight: weight, goalWeight: goalWeight, weightUnit: weightUnit)
    }
    public var ageError: String? { FieldLimits.rangeError(age, FieldLimits.age) }
    public var weightError: String? { FieldLimits.rangeError(weight, FieldLimits.weight) }
    public var calorieTargetError: String? { FieldLimits.rangeError(dailyCalorieTarget, FieldLimits.dailyCalorieTarget) }
    public var stepTargetError: String? { FieldLimits.rangeError(dailyStepTarget, FieldLimits.dailyStepTarget) }
    public var cardioMinutesError: String? {
        cardioDays.isEmpty ? nil : FieldLimits.rangeError(cardioMinutes, FieldLimits.cardioMinutes)
    }

    /// The strict number of off-days plus one day of scheduling slack.
    public var maxPreferredRestDays: Int { 7 - trainingDays + 1 }
    public var tooManyPreferredRestDays: Bool { preferredRestDays.count > maxPreferredRestDays }

    public var steps: [OnboardingStep] { OnboardingOptions.steps(for: mode) }

    public func canAdvance(from step: OnboardingStep) -> Bool {
        switch step {
        case .mode: !mode.isEmpty
        case .bodyStats: ageError == nil && weightError == nil
        case .goal: !goal.isEmpty && goalWeightError == nil
        case .experience: !experience.isEmpty
        case .preferredRestDays: !tooManyPreferredRestDays
        case .equipment: !equipment.isEmpty
        case .targets: calorieTargetError == nil && stepTargetError == nil && cardioMinutesError == nil
        default: true
        }
    }

    public var selectedMuscleCount: Int { priorityMuscles.filter { $0 != OnboardingOptions.noPreference }.count }

    // MARK: Toggles

    /// Picking a weight goal keeps the target; General fitness clears it.
    public mutating func selectGoal(_ value: String) {
        goal = value
        if !OnboardingOptions.weightGoals.contains(value) { goalWeight = "" }
    }

    public mutating func toggleActivity(_ value: String) {
        activityLevel = activityLevel == value ? "" : value
    }

    public mutating func togglePreferredRestDay(_ value: String) {
        if preferredRestDays.contains(value) { preferredRestDays.removeAll { $0 == value } } else { preferredRestDays.append(value) }
    }

    public mutating func toggleCardioDay(_ value: String) {
        if cardioDays.contains(value) { cardioDays.removeAll { $0 == value } } else { cardioDays.append(value) }
    }

    /// "Full gym" is exclusive: picking it clears the rest, picking anything else drops it.
    public mutating func toggleEquipment(_ item: String) {
        if item == "Full gym" {
            equipment = equipment.contains("Full gym") ? [] : ["Full gym"]
            return
        }
        let withoutFullGym = equipment.filter { $0 != "Full gym" }
        equipment = withoutFullGym.contains(item) ? withoutFullGym.filter { $0 != item } : withoutFullGym + [item]
    }

    /// Up to three; "No preference" is exclusive.
    public mutating func toggleMuscle(_ item: String) {
        if item == OnboardingOptions.noPreference { priorityMuscles = [OnboardingOptions.noPreference]; return }
        let filtered = priorityMuscles.filter { $0 != OnboardingOptions.noPreference }
        if filtered.contains(item) { priorityMuscles = filtered.filter { $0 != item }; return }
        if filtered.count >= 3 { return }
        priorityMuscles = filtered + [item]
    }

    public mutating func toggleSex(_ value: String) {
        sex = sex == value ? "" : value
    }

    /// Clearing the injury text clears its severity too.
    public mutating func setInjuries(_ text: String) {
        injuries = text
        if text.isEmpty { injurySeverity = "" }
    }

    public mutating func toggleInjurySeverity(_ value: String) {
        injurySeverity = injurySeverity == value ? "" : value
    }

    /// First visit to the targets step: fill blanks with a starting point.
    public mutating func seedTargets() {
        if dailyCalorieTarget.isEmpty {
            dailyCalorieTarget = String(OnboardingOptions.suggestCalories(weight: weight, weightUnit: weightUnit, goal: goal))
        }
        if dailyStepTarget.isEmpty { dailyStepTarget = "8000" }
    }

    // MARK: Review

    public struct ReviewRow: Sendable, Equatable {
        public var label: String
        public var value: String
    }

    /// The review step's rows, in the web's order, skipping blanks.
    public var reviewRows: [ReviewRow] {
        var rows: [ReviewRow] = []
        func add(_ cond: Bool, _ label: String, _ value: @autoclosure () -> String?) {
            // JS renders `undefined` as an empty cell; keep the row like the web does.
            if cond { rows.append(ReviewRow(label: label, value: value() ?? "")) }
        }
        let isAI = mode == "ai"
        add(true, "Mode", isAI ? "AI Coach" : "Independent")
        add(!name.isEmpty, "Name", name)
        add(!goal.isEmpty, "Goal", OnboardingOptions.goalLabel(goal))
        add(!goalWeight.isEmpty, "Goal weight", "\(goalWeight) \(weightUnit)")
        add(!experience.isEmpty, "Experience", OnboardingOptions.experience.first { $0.value == experience }?.label)
        add(!activityLevel.isEmpty, "Activity level", OnboardingOptions.activity.first { $0.value == activityLevel }?.label)
        add(isAI, "Training days", "\(trainingDays) days/week")
        add(!preferredRestDays.isEmpty, "Rest days", preferredRestDays.map { d in
            OnboardingOptions.weekdays.first { $0.value == d }?.label ?? ""
        }.joined(separator: ", "))
        add(!equipment.isEmpty, "Equipment", equipment.joined(separator: ", "))
        add(!age.isEmpty, "Age", age)
        add(!sex.isEmpty, "Sex", sex)
        add(!weight.isEmpty, "Weight", "\(weight) \(weightUnit)")
        add(!injuries.isEmpty, "Injuries", injuries)
        add(!injuries.isEmpty && !injurySeverity.isEmpty, "Severity",
            OnboardingOptions.injurySeverity.first { $0.value == injurySeverity }?.label)
        add(!priorityMuscles.isEmpty, "Priority muscles", priorityMuscles.joined(separator: ", "))
        add(!isAI && !dailyCalorieTarget.isEmpty, "Calorie target",
            "\(Self.localeInt(dailyCalorieTarget)) kcal/day")
        add(!isAI && !dailyStepTarget.isEmpty, "Step target",
            "\(Self.localeInt(dailyStepTarget)) steps/day")
        if !isAI && !cardioDays.isEmpty {
            let days = IndependentTargets.orderCardioDays(cardioDays).joined(separator: ", ")
            rows.append(ReviewRow(label: "Cardio", value: days + (cardioMinutes.isEmpty ? "" : " · \(cardioMinutes) min each")))
        }
        return rows
    }

    /// `parseInt(s, 10).toLocaleString()` in en-US.
    static func localeInt(_ s: String) -> String {
        let n = JS.parseInt(s, radix: 10)
        return n.isFinite ? JS.groupedEnUS(n) : "NaN"
    }

    // MARK: createProfile values

    /// The web's `x ? parseInt(x) : undefined`. NaN becomes nil (JSON.stringify
    /// writes NaN as null).
    public static func intOrNil(_ s: String) -> Int? {
        guard !s.isEmpty else { return nil }
        let n = JS.parseInt(s, radix: 10)
        return n.isFinite ? Int(n) : nil
    }

    /// The web's `x ? parseFloat(x) : undefined`, NaN as nil.
    public static func doubleOrNil(_ s: String) -> Double? {
        guard !s.isEmpty else { return nil }
        let n = JS.parseFloat(s)
        return n.isFinite ? n : nil
    }

    public var payloadCardioMinutes: Int? {
        !cardioDays.isEmpty && !cardioMinutes.isEmpty ? Self.intOrNil(cardioMinutes) : nil
    }

    public var payloadInjurySeverity: String? {
        !injuries.isEmpty && !injurySeverity.isEmpty ? injurySeverity : nil
    }
}

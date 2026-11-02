import Foundation

// Port of lib/nutritionPlan.ts. There is no meal-plan data in the backend yet:
// programs only carry `dailyCalorieTarget`, so the nutrition page runs on
// `samplePlan`, scaled to the user's real calorie target.

public enum MealSlot: String, Sendable, Codable, CaseIterable {
    case breakfast, lunch
    case preWorkout = "pre_workout"
    case postWorkout = "post_workout"
    case dinner
}

public struct Macros: Sendable, Equatable, Codable {
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public init(protein: Double, carbs: Double, fat: Double) { self.protein = protein; self.carbs = carbs; self.fat = fat }
}

public struct MacroTotals: Sendable, Equatable, Codable {
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var kcal: Double
}

public enum FoodUnit: String, Sendable, Codable, CaseIterable {
    case g, ml, pcs, medium, bowl
    /// Weighed units scale with the plan; countable ones (a banana, a bowl) don't.
    public var isMeasure: Bool { self == .g || self == .ml }
}

public struct Food: Sendable, Equatable, Codable {
    public var name: String
    public var amount: Double
    public var unit: FoodUnit
    public init(name: String, amount: Double, unit: FoodUnit) { self.name = name; self.amount = amount; self.unit = unit }
}

public struct Meal: Sendable, Equatable, Codable {
    public var slot: MealSlot
    public var label: String
    public var macros: Macros
    public var foods: [Food]
}

public struct NutritionPlan: Sendable, Equatable, Codable {
    public var meals: [Meal]
    public init(meals: [Meal]) { self.meals = meals }

    /// Atwater factors: 4 kcal/g protein or carbs, 9 kcal/g fat (rounded, JS-style).
    public static func kcalOf(_ m: Macros) -> Double {
        JS.round(m.protein * 4 + m.carbs * 4 + m.fat * 9)
    }

    /// Summed macros, and kcal summed per meal (so it matches the meal cards).
    public var totals: MacroTotals {
        var p = 0.0, c = 0.0, f = 0.0, k = 0.0
        for meal in meals {
            p += meal.macros.protein; c += meal.macros.carbs; f += meal.macros.fat
            k += Self.kcalOf(meal.macros)
        }
        return MacroTotals(protein: p, carbs: c, fat: f, kcal: k)
    }

    /// Every macro and every weighed food scaled by `kcalTarget / totals.kcal`
    /// (foods to the nearest 5, at least 5). Unchanged without a positive target.
    public func scaled(toKcal kcalTarget: Double?) -> NutritionPlan {
        let base = totals.kcal
        guard let kcalTarget, kcalTarget > 0, base > 0 else { return self }
        let ratio = kcalTarget / base
        return NutritionPlan(meals: meals.map { meal in
            Meal(slot: meal.slot, label: meal.label,
                 macros: Macros(protein: JS.round(meal.macros.protein * ratio), carbs: JS.round(meal.macros.carbs * ratio),
                                fat: JS.round(meal.macros.fat * ratio)),
                 foods: meal.foods.map { food in
                     guard food.unit.isMeasure else { return food }
                     return Food(name: food.name, amount: Swift.max(5, JS.round(food.amount * ratio / 5) * 5), unit: food.unit)
                 })
        })
    }

    /// "½", "2 medium", "1 bowl", "2 bowls", "80 g".
    public static func formatAmount(_ food: Food) -> String {
        switch food.unit {
        case .medium: return food.amount == 0.5 ? "½" : "\(JS.string(food.amount)) medium"
        case .bowl: return food.amount == 1 ? "1 bowl" : "\(JS.string(food.amount)) bowls"
        default: return "\(JS.string(food.amount)) \(food.unit.rawValue)"
        }
    }

    /// A ~2,450 kcal training-day plan: 180 P / 270 C / 72 F.
    public static let sample = NutritionPlan(meals: [
        Meal(slot: .breakfast, label: "Breakfast", macros: Macros(protein: 42, carbs: 68, fat: 14), foods: [
            Food(name: "Oats", amount: 80, unit: .g),
            Food(name: "Whey protein", amount: 30, unit: .g),
            Food(name: "Blueberries", amount: 100, unit: .g),
            Food(name: "Peanut butter", amount: 15, unit: .g),
        ]),
        Meal(slot: .lunch, label: "Lunch", macros: Macros(protein: 55, carbs: 78, fat: 18), foods: [
            Food(name: "Chicken breast", amount: 180, unit: .g),
            Food(name: "Jasmine rice, dry", amount: 90, unit: .g),
            Food(name: "Broccoli", amount: 150, unit: .g),
            Food(name: "Olive oil", amount: 10, unit: .ml),
        ]),
        Meal(slot: .preWorkout, label: "Pre-workout", macros: Macros(protein: 22, carbs: 56, fat: 2), foods: [
            Food(name: "Greek yogurt 0%", amount: 200, unit: .g),
            Food(name: "Banana", amount: 1, unit: .medium),
            Food(name: "Honey", amount: 15, unit: .g),
        ]),
        Meal(slot: .postWorkout, label: "Post-workout", macros: Macros(protein: 32, carbs: 48, fat: 3), foods: [
            Food(name: "Whey protein", amount: 35, unit: .g),
            Food(name: "Rice cakes", amount: 3, unit: .pcs),
            Food(name: "Jam", amount: 20, unit: .g),
        ]),
        Meal(slot: .dinner, label: "Dinner", macros: Macros(protein: 29, carbs: 20, fat: 35), foods: [
            Food(name: "Salmon", amount: 150, unit: .g),
            Food(name: "Potatoes", amount: 300, unit: .g),
            Food(name: "Side salad", amount: 1, unit: .bowl),
            Food(name: "Avocado", amount: 0.5, unit: .medium),
        ]),
    ])
}

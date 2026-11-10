import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// Debug states CI screenshots (see DebugScreen).
enum NutritionDebug {
    case none
    /// The first meal (breakfast) opened.
    case open
}

/// The Nutrition tab (port of pages/nutrition.tsx): the daily target as a log-page
/// stat band, then one card per meal that opens into its macros and foods. Runs on
/// `NutritionPlan.sample` scaled to the user's calorie target until meal plans exist
/// in the backend. Rules from the design rounds: no meal times, no "share of day",
/// monochrome macros.
struct NutritionScreen: View {
    @Environment(AppServices.self) private var services
    @State private var data = NutritionData()
    /// One meal open at a time, like the inset rows on the log page.
    @State private var openSlot: MealSlot?
    private let debug: NutritionDebug

    init(debug: NutritionDebug = .none) {
        self.debug = debug
        _openSlot = State(initialValue: debug == .open ? .breakfast : nil)
    }

    var body: some View {
        let target = data.kcalTarget
        let plan = NutritionPlan.sample.scaled(toKcal: target.map(Double.init))
        let totals = plan.totals
        IntentPage {
            header
            dailyTarget(target: target, totals: totals)
            VStack(alignment: .leading, spacing: 0) {
                IntentSectionTitle("Meals")
                VStack(spacing: 10) {
                    ForEach(plan.meals, id: \.slot) { meal in
                        NutritionMealCard(meal: meal, isOpen: openSlot == meal.slot) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                openSlot = openSlot == meal.slot ? nil : meal.slot
                            }
                        }
                    }
                }
            }
            sampleNotice(target: target)
        }
        .task { await data.load(services.api) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        // No nav bar: keep a black band under the status bar so scrolled content doesn't run behind the clock.
        .overlay(alignment: .top) {
            Color.intent.background.ignoresSafeArea(edges: .top).frame(height: 0)
        }
    }

    // MARK: Header

    private var header: some View {
        IntentPageHeader("Nutrition") {
            // Web: shown when there's a phase or the program is AI-generated.
            if let phase = data.phaseLine {
                Text(phase)
            }
            if data.showsAIBadge {
                IntentBadge("AI Coach", tint: .accent)
            }
        }
    }

    // MARK: Daily target

    private func dailyTarget(target: Int?, totals: MacroTotals) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Daily target")
                .intentText(.caps)
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)
            IntentDivider()
            HStack(spacing: 0) {
                // The real target when there is one: the scaled meals round to within a few kcal of it.
                NutritionStatCell(value: NutritionFormat.grouped(Double(target ?? Int(totals.kcal))), unit: nil, label: "kcal")
                    .padding(.leading, 20)
                    .frame(width: 100, alignment: .leading)
                macroCell(totals.protein, "Protein")
                macroCell(totals.carbs, "Carbs")
                macroCell(totals.fat, "Fat")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .intentSurface(radius: IntentRadius.groupedList)
    }

    private func macroCell(_ grams: Double, _ label: String) -> some View {
        HStack(spacing: 0) {
            IntentDivider(.vertical)
            NutritionStatCell(value: NutritionFormat.number(grams), unit: "g", label: label)
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Notice

    private func sampleNotice(target: Int?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .light))
                .padding(.top, 1)
            Text("This is a sample meal plan\(target.map { ", sized to your \(NutritionFormat.grouped(Double($0))) kcal target" } ?? ""). Your own plan will replace it here.")
                .font(.intent(12.5))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.intent.mutedForeground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .intentSurface(radius: IntentRadius.notice)
    }
}

/// `toLocaleString()` in en-US ("3,100") and plain gram counts.
enum NutritionFormat {
    /// Whole kcal with thousands commas (the values here are always integers).
    static func grouped(_ value: Double) -> String {
        let whole = Int(value.rounded())
        let digits = String(abs(whole))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (whole < 0 ? "-" : "") + out
    }

    /// A whole gram count as JS prints it (no ".0").
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// One column of the log page's stat band: a big light number over a caps label.
private struct NutritionStatCell: View {
    let value: String
    let unit: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .intentText(.statInput)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.intent(13))
                        .foregroundStyle(Color.intent.mutedForeground)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(label)
                .font(.intent(10))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color.intent.mutedForeground)
                .lineLimit(1)
        }
        .padding(.vertical, 14)
    }
}

/// A meal card: icon circle, name, big light kcal, chevron; opens into its P/C/F band
/// and its foods.
private struct NutritionMealCard: View {
    let meal: Meal
    let isOpen: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 14) {
                    Image(systemName: Self.icon(meal.slot))
                        .font(.system(size: 17, weight: .light))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.intent.secondary))
                    Text(meal.label)
                        .font(.intent(15))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(NutritionFormat.number(NutritionPlan.kcalOf(meal.macros)))
                            .font(.intent(24, .light))
                            .tracking(-0.48)
                            .monospacedDigit()
                        Text("kcal")
                            .font(.intent(10))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.intent.mutedForeground)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundStyle(Color.intent.foreground)
                .padding(.vertical, 14)
                .padding(.leading, 14)
                .padding(.trailing, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(NutritionCardButtonStyle())
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

            if isOpen {
                VStack(spacing: 0) {
                    IntentDivider()
                    macroBand
                    ForEach(Array(meal.foods.enumerated()), id: \.offset) { _, food in
                        IntentDivider()
                        HStack(spacing: 12) {
                            Text(food.name).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(NutritionPlan.formatAmount(food))
                                .monospacedDigit()
                                .foregroundStyle(Color.intent.mutedForeground)
                                .fixedSize()
                        }
                        .font(.intent(14))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.intent.card)
        .clipShape(RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous))
    }

    private var macroBand: some View {
        let cells: [(String, Double)] = [("Protein", meal.macros.protein), ("Carbs", meal.macros.carbs), ("Fat", meal.macros.fat)]
        return HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                HStack(spacing: 0) {
                    if i > 0 { IntentDivider(.vertical) }
                    NutritionStatCell(value: NutritionFormat.number(cell.1), unit: "g", label: cell.0)
                        .padding(.leading, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// lucide Sunrise / Sandwich / Zap / BatteryCharging / Moon. SF Symbols has no
    /// sandwich, so lunch gets the fork and knife.
    static func icon(_ slot: MealSlot) -> String {
        switch slot {
        case .breakfast: "sunrise"
        case .lunch: "fork.knife"
        case .preWorkout: "bolt"
        case .postWorkout: "battery.100percent.bolt"
        case .dinner: "moon"
        }
    }
}

private struct NutritionCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.intent.accent.opacity(0.4) : Color.clear)
    }
}

/// What the page reads: the profile (mode + Independent target) and the current program
/// (AI target, phase, week).
@MainActor
@Observable
final class NutritionData {
    var isIndependent = false
    var profileTarget: Int?
    var programTarget: Int?
    var shortTermPhase: String?
    var weekInPhase: Int?
    var aiGenerated = false

    var kcalTarget: Int? {
        SettingsLogic.nutritionTarget(isIndependent: isIndependent, profileTarget: profileTarget, programTarget: programTarget)
    }

    var phaseLine: String? {
        isIndependent ? nil : SettingsLogic.phaseLine(shortTermPhase: shortTermPhase, weekInPhase: weekInPhase)
    }

    var showsAIBadge: Bool { !isIndependent && aiGenerated }

    func load(_ client: IntentAPIClient) async {
        async let profileReq = Self.fetchProfile(client.api)
        async let programReq = Self.fetchProgram(client.api)
        if let profile = await profileReq {
            isIndependent = profile.mode == "independent"
            profileTarget = profile.dailyCalorieTarget
        }
        if let program = await programReq {
            programTarget = program.dailyCalorieTarget
            shortTermPhase = program.shortTermPhase?.rawValue
            weekInPhase = program.weekInPhase
            aiGenerated = program.aiGenerated
        }
    }

    nonisolated private static func fetchProfile(_ api: Client) async -> IntentSchemas.UserProfile? {
        try? await api.getProfile().ok.body.json
    }

    nonisolated private static func fetchProgram(_ api: Client) async -> IntentSchemas.Program? {
        try? await api.getCurrentProgram().ok.body.json
    }
}

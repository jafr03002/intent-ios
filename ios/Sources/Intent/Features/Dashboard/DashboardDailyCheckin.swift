import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// "Today's check-in" (pages/dashboard.tsx): weight (bodyweight logging), calories,
/// steps and cardio in four tiles, one Save. Pre-filled from today's saved entry.
struct DashboardDailyCheckin: View {
    let model: DashboardModel
    let client: IntentAPIClient

    @State private var weight = ""
    @State private var calories = ""
    @State private var steps = ""
    @State private var cardioType = ""
    @State private var cardioMinutes = ""
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var prefilled = false

    static let cardioTypes = ["Run", "Bike", "Row", "Swim", "Walk", "Other"]

    private var todayEntry: IntentSchemas.DailyLogWeekEntry? { model.todayEntry }
    /// No program yet: daily targets don't exist, so the check-in is locked.
    private var locked: Bool { model.program == nil }
    private var weightUnit: String { model.profile?.weightUnit ?? "kg" }

    private var weightError: String? { FieldLimits.rangeError(weight, FieldLimits.weight) }
    private var caloriesError: String? { FieldLimits.rangeError(calories, FieldLimits.calories) }
    private var stepsError: String? { FieldLimits.rangeError(steps, FieldLimits.steps) }
    private var cardioMinutesError: String? { FieldLimits.rangeError(cardioMinutes, FieldLimits.cardioMinutes) }
    private var firstError: String? { weightError ?? caloriesError ?? stepsError ?? cardioMinutesError }

    private var loggedCount: Int {
        DashboardLogic.loggedCount(weight: todayEntry?.weight, calories: todayEntry?.calories,
                                   steps: todayEntry?.steps, cardioType: todayEntry?.cardioType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Today's check-in").intentText(.sectionTitle).foregroundStyle(Color.intent.foreground)
                Spacer(minLength: 0)
                Text("\(loggedCount)/4 logged")
                    .intentText(.badge)
                    .lineLimit(1)
                    .foregroundStyle(loggedCount == 4 ? Color.black : Color.intent.mutedForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(loggedCount == 4 ? Color.white : Color.intent.secondary))
            }
            .padding(.bottom, IntentSpacing.sectionTitle)

            VStack(alignment: .leading, spacing: 0) {
                if locked {
                    Text("Generate a program to start logging your daily check-in.")
                        .intentText(.caption)
                        .foregroundStyle(Color.intent.mutedForeground)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        tile("Weight", done: todayEntry?.weight != nil, error: weightError != nil) {
                            numberField("0.0", text: $weight, decimal: true)
                            unit(weightUnit)
                        }
                        tile("Calories", done: todayEntry?.calories != nil, error: caloriesError != nil) {
                            numberField("0", text: $calories)
                            unit("kcal")
                        }
                    }
                    GridRow {
                        tile("Steps", done: todayEntry?.steps != nil, error: stepsError != nil) {
                            numberField("0", text: $steps)
                        }
                        tile("Cardio", done: todayEntry?.cardioType != nil, error: cardioMinutesError != nil) {
                            cardioPicker
                            TextField("", text: $cardioMinutes, prompt: Text("min").foregroundColor(Color.intent.mutedForeground))
                                .keyboardType(.numberPad)
                                .font(.intent(15))
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                                .disabled(locked)
                        }
                    }
                }
                .opacity(locked ? 0.5 : 1)

                if let firstError {
                    Text(firstError)
                        .font(.intent(12, .medium))
                        .foregroundStyle(Color.intent.destructive)
                        .padding(.horizontal, 8)
                        .padding(.top, 10)
                }
                if saveFailed {
                    Text("Couldn't save your check-in. Please try again.")
                        .font(.intent(12, .medium))
                        .foregroundStyle(Color.intent.destructive)
                        .padding(.horizontal, 8)
                        .padding(.top, 10)
                }

                Button(isSaving ? "Saving..." : "Save today's check-in") { Task { await save() } }
                    .buttonStyle(.intentPrimary)
                    .disabled(isSaving || locked || firstError != nil)
                    .padding(.top, 12)
            }
            .padding(12)
            .intentSurface(radius: IntentRadius.groupedList)
        }
        .onAppear(perform: prefill)
        .onChange(of: model.week) { _, _ in prefill() }
    }

    // Only on load, so a background refresh doesn't clobber what's being typed.
    private func prefill() {
        guard !prefilled, let e = todayEntry else { return }
        prefilled = true
        weight = e.weight.map(DashboardFormat.js) ?? ""
        calories = e.calories.map(String.init) ?? ""
        steps = e.steps.map(String.init) ?? ""
        cardioType = e.cardioType ?? ""
        cardioMinutes = e.cardioMinutes.map(String.init) ?? ""
    }

    private var cardioPicker: some View {
        Menu {
            Button("None") { cardioType = "" }
            ForEach(Self.cardioTypes, id: \.self) { t in
                Button(t) { cardioType = t }
            }
        } label: {
            HStack(spacing: 4) {
                Text(cardioType.isEmpty ? "None" : cardioType)
                    .font(.intent(15))
                    .foregroundStyle(Color.intent.foreground)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.intent.foreground)
                Spacer(minLength: 0)
            }
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .disabled(locked)
        .frame(maxWidth: .infinity)
    }

    private func numberField(_ placeholder: String, text: Binding<String>, decimal: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color.intent.mutedForeground.opacity(0.5)))
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .font(.intent(24, .light))
            .tracking(-0.48)
            .monospacedDigit()
            .foregroundStyle(Color.intent.foreground)
            .disabled(locked)
            .frame(maxWidth: .infinity)
            // A Swedish decimal pad types "82,5"; the web's number input reads it as 82.5.
            .onChange(of: text.wrappedValue) { _, v in
                if decimal, v.contains(",") { text.wrappedValue = v.replacingOccurrences(of: ",", with: ".") }
            }
    }

    private func unit(_ text: String) -> some View {
        Text(text).font(.intent(12)).foregroundStyle(Color.intent.mutedForeground).fixedSize()
    }

    private func tile<Content: View>(_ label: String, done: Bool, error: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label).font(.intent(10.5)).tracking(1.05).textCase(.uppercase)
                    .foregroundStyle(Color.intent.mutedForeground)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.intent.chart2)
                }
            }
            HStack(spacing: 6) { content() }
                .frame(minHeight: 32)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.intent.secondary))
        .overlay {
            if error {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.intent.destructive, lineWidth: 1)
            }
        }
    }

    private func save() async {
        guard firstError == nil, !locked else { return }
        let w = Double(weight.trimmingCharacters(in: .whitespaces))
        let c = Int(calories.trimmingCharacters(in: .whitespaces))
        let s = Int(steps.trimmingCharacters(in: .whitespaces))
        let m = Int(cardioMinutes.trimmingCharacters(in: .whitespaces))
        let input = IntentSchemas.DailyCheckinInput(
            date: model.today,
            weight: w.flatMap { $0.isFinite ? $0 : nil },
            calories: c, steps: s,
            cardioType: cardioType.isEmpty ? nil : cardioType,
            cardioMinutes: m)
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        do {
            _ = try await client.api.submitDailyCheckin(body: .json(input)).ok.body.json
        } catch {
            saveFailed = true
            return
        }
        // The upsert keeps fields that weren't sent; mirror it locally (the mock
        // backend is stateless), then refresh what the save feeds.
        var week = model.week ?? IntentSchemas.DailyLogsWeekResult(days: [])
        var entry = model.todayEntry ?? IntentSchemas.DailyLogWeekEntry(date: model.today)
        if let v = input.weight { entry.weight = v; entry.weightUnit = weightUnit }
        if let v = input.calories { entry.calories = v }
        if let v = input.steps { entry.steps = v }
        if let v = input.cardioType { entry.cardioType = v }
        if let v = input.cardioMinutes { entry.cardioMinutes = v }
        if let i = week.days.firstIndex(where: { $0.date == model.today }) { week.days[i] = entry } else { week.days.append(entry) }
        model.week = week
        await model.reloadGoalAndProfile(client)
    }
}

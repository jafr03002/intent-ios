import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// components/dashboard/IndependentTargetsCard.tsx: Independent mode's editable
/// stand-in for the AI narrative. Phase is the profile goal, so a goal-weight phase
/// (bulk/diet) needs a target pointing the right way, and switching to maintenance
/// clears the target only after a confirm.
struct DashboardIndependentTargets: View {
    let model: DashboardModel
    let client: IntentAPIClient
    let profile: IntentSchemas.UserProfile

    @State private var editing: Bool
    @State private var phase: IndependentPhase = .maintenance
    @State private var goalWeight = ""
    @State private var calories = ""
    @State private var steps = ""
    @State private var cardioDays: [String] = []
    @State private var cardioMinutes = ""
    @State private var confirmClear = false
    @State private var isSaving = false
    @State private var saveFailed = false

    init(model: DashboardModel, client: IntentAPIClient, profile: IntentSchemas.UserProfile, startEditing: Bool = false) {
        self.model = model
        self.client = client
        self.profile = profile
        _editing = State(initialValue: false)
        self.startEditing = startEditing
    }

    private let startEditing: Bool
    private var weightUnit: String { profile.weightUnit ?? "kg" }
    private var savedPhase: IndependentPhase { IndependentTargets.goalToPhase(profile.goal) }

    var body: some View {
        Group {
            if editing { editor } else { viewer }
        }
        .onAppear { if startEditing && !editing { openEditor() } }
        .alert("Clear your goal weight?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Yes, clear it", role: .destructive) { phase = .maintenance; goalWeight = "" }
        } message: {
            Text("General fitness has no target weight, so switching will set your goal weight\(profile.goalWeight.map { " (\(DashboardFormat.js($0)) \(weightUnit))" } ?? "") back to scratch. Your progress graph will stop tracking toward a target — you can set a new one anytime by picking Bulk or Diet.")
        }
    }

    // MARK: View mode

    private var viewer: some View {
        let opt = IndependentTargets.phaseOption(savedPhase)
        let accent = dashboardColor(PhaseColors.hues[savedPhase.shortTermPhase]!)
        let hasAny = profile.dailyCalorieTarget != nil || profile.dailyStepTarget != nil || !(profile.cardioDays ?? []).isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(accent).frame(width: 8, height: 8)
                    Text(opt.tag).font(.intent(12, .semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(accent)
                        .fixedSize()
                    Text("· \(opt.heading.lowercased())").font(.intent(12)).foregroundStyle(Color.intent.mutedForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { openEditor() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil").font(.system(size: 11, weight: .medium))
                        Text("Edit").font(.intent(12, .medium))
                    }
                    .foregroundStyle(Color.intent.foreground)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.intent.secondary))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            if hasAny || profile.goalWeight != nil {
                VStack(spacing: 8) {
                    row("Goal weight", divider: true) {
                        if savedPhase == .maintenance {
                            Text("— no target").font(.intent(14)).foregroundStyle(Color.intent.mutedForeground)
                        } else if let gw = profile.goalWeight {
                            valueText(DashboardFormat.js(gw), unit: weightUnit)
                        } else {
                            notSet
                        }
                    }
                    row("Calorie target", divider: true) {
                        if let v = profile.dailyCalorieTarget { valueText(DashboardFormat.grouped(v), unit: "kcal / day") } else { notSet }
                    }
                    row("Step target", divider: true) {
                        if let v = profile.dailyStepTarget { valueText(DashboardFormat.grouped(v), unit: "steps / day") } else { notSet }
                    }
                    row("Cardio", divider: false) {
                        let days = IndependentTargets.orderCardioDays(profile.cardioDays ?? [])
                        if days.isEmpty && (profile.cardioDays ?? []).isEmpty {
                            Text("None").font(.intent(14)).foregroundStyle(Color.intent.mutedForeground)
                        } else {
                            HStack(spacing: 6) {
                                ForEach(days, id: \.self) { d in
                                    Text(d).font(.intent(11, .medium)).foregroundStyle(Color.intent.foreground)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.intent.secondary))
                                }
                                if let m = profile.cardioMinutes {
                                    Text("· \(m) min each").font(.intent(12, .medium)).foregroundStyle(Color.intent.mutedForeground)
                                        .fixedSize()
                                }
                            }
                        }
                    }
                }
            } else {
                (Text("No targets set yet. Tap ") + Text("Edit").foregroundColor(Color.intent.foreground)
                    + Text(" to add your calorie, step, and cardio targets — you can change them anytime."))
                    .font(.intent(14))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .padding(.vertical, 8)
            }
        }
        .padding(20)
        .intentSurface(radius: IntentRadius.groupedList)
    }

    private var notSet: some View {
        Text("Not set").font(.intent(14)).foregroundStyle(Color.intent.mutedForeground)
    }

    private func valueText(_ value: String, unit: String) -> some View {
        (Text(value).font(.intent(14, .semibold)).foregroundColor(Color.intent.foreground)
            + Text(" \(unit)").font(.intent(12, .medium)).foregroundColor(Color.intent.mutedForeground))
            .lineLimit(1)
    }

    private func row<V: View>(_ label: String, divider: Bool, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.intent(14)).foregroundStyle(Color.intent.mutedForeground).fixedSize()
            Spacer(minLength: 0)
            value()
        }
        .padding(.vertical, 4)
        .padding(.bottom, divider ? 4 : 0)
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(Color.intent.border.opacity(0.5)).frame(height: 1) }
        }
    }

    // MARK: Edit mode

    private func openEditor() {
        phase = savedPhase
        goalWeight = profile.goalWeight.map(DashboardFormat.js) ?? ""
        calories = profile.dailyCalorieTarget.map(String.init) ?? ""
        steps = profile.dailyStepTarget.map(String.init) ?? ""
        cardioDays = profile.cardioDays ?? []
        cardioMinutes = profile.cardioMinutes.map(String.init) ?? ""
        confirmClear = false
        saveFailed = false
        editing = true
    }

    private func pickPhase(_ next: IndependentPhase) {
        if next == phase { return }
        if next == .maintenance && !goalWeight.trimmingCharacters(in: .whitespaces).isEmpty {
            confirmClear = true
            return
        }
        phase = next
        if next == .maintenance { goalWeight = "" }
    }

    private var goalError: String? {
        IndependentTargets.phaseGoalWeightError(phase: phase, currentWeight: profile.weight, goalWeight: goalWeight, unit: weightUnit)
    }
    private var caloriesError: String? { FieldLimits.rangeError(calories, FieldLimits.dailyCalorieTarget) }
    private var stepsError: String? { FieldLimits.rangeError(steps, FieldLimits.dailyStepTarget) }
    private var cardioMinutesError: String? {
        cardioDays.isEmpty ? nil : FieldLimits.rangeError(cardioMinutes, FieldLimits.cardioMinutes)
    }
    private var hasRangeError: Bool { caloriesError != nil || stepsError != nil || cardioMinutesError != nil }

    private var editor: some View {
        let showGoalError = goalError != nil && !goalWeight.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Text("Edit your targets").font(.intent(14, .semibold)).tracking(0.7).textCase(.uppercase)
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.bottom, 16)

            capsLabel("Phase — pick your goal")
            VStack(spacing: 10) {
                ForEach(IndependentTargets.phaseOptions, id: \.phase) { o in
                    phaseCard(o)
                }
            }
            .padding(.top, 8)

            if phase == .maintenance {
                (Text("General fitness has no goal weight.").foregroundColor(Color.intent.foreground)
                    + Text(" Your progress graph stops tracking toward a target until you pick Bulk or Diet again."))
                    .font(.intent(12.5))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .lineSpacing(3)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.intent.secondary))
                    .padding(.top, 12)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Goal weight").font(.intent(13)).foregroundStyle(Color.intent.foreground)
                        Text("Required").font(.intent(9.5)).tracking(0.95).textCase(.uppercase)
                            .foregroundStyle(showGoalError ? Color.intent.destructive : Color.intent.mutedForeground)
                    }
                    pillField("Target \(weightUnit)", text: $goalWeight, unit: weightUnit, fill: Color.intent.card, decimal: true)
                    if showGoalError, let goalError {
                        errorText(goalError)
                    } else if let w = profile.weight {
                        Text("Enter a target \(phase == .bulk ? "above" : "below") your current \(DashboardFormat.js(w)) \(weightUnit).")
                            .font(.intent(12)).foregroundStyle(Color.intent.mutedForeground)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.intent.secondary))
                .overlay {
                    if showGoalError {
                        RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.intent.destructive, lineWidth: 1)
                    }
                }
                .padding(.top, 12)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    capsLabel("Calorie target")
                    pillField("0", text: $calories, unit: "kcal / day", error: caloriesError != nil)
                    if let caloriesError { errorText(caloriesError) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    capsLabel("Step target")
                    pillField("0", text: $steps, unit: "steps / day", error: stepsError != nil)
                    if let stepsError { errorText(stepsError) }
                }
            }
            .padding(.vertical, 20)

            capsLabel("Cardio — which days & how long")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(IndependentTargets.cardioDays, id: \.self) { d in
                        let on = cardioDays.contains(d)
                        Button {
                            if on { cardioDays.removeAll { $0 == d } } else { cardioDays.append(d) }
                        } label: {
                            Text(d).font(.intent(12, on ? .medium : .regular))
                                .foregroundStyle(on ? Color.black : Color.intent.mutedForeground)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(on ? Color.white : Color.intent.secondary))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, 8)
            pillField("min", text: $cardioMinutes, unit: "min", error: cardioMinutesError != nil, height: 44)
                .frame(width: 128)
                .padding(.top, 12)
            if let cardioMinutesError {
                errorText(cardioMinutesError).padding(.top, 8)
            } else {
                Text("Tap the days you'll do cardio; the minutes apply to each of those days.")
                    .font(.intent(12)).foregroundStyle(Color.intent.mutedForeground).padding(.top, 8)
            }
            if saveFailed {
                errorText("Couldn't save your targets. Please try again.").padding(.top, 8)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { editing = false }
                    .buttonStyle(DashboardSmallPillStyle(primary: false))
                    .disabled(isSaving)
                Button(isSaving ? "Saving..." : "Save targets") { Task { await save() } }
                    .buttonStyle(DashboardSmallPillStyle(primary: true))
                    .disabled(isSaving || goalError != nil || hasRangeError)
            }
            .padding(.top, 20)
        }
        .padding(20)
        .intentSurface(radius: IntentRadius.groupedList)
    }

    private func phaseCard(_ o: PhaseOption) -> some View {
        let selected = phase == o.phase
        let c = dashboardColor(PhaseColors.hues[o.phase.shortTermPhase]!)
        return Button { pickPhase(o.phase) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Circle().fill(c).frame(width: 10, height: 10)
                    Text(o.heading).font(.intent(15, .medium))
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                }
                Text(o.tag).font(.intent(11)).tracking(1.1).textCase(.uppercase)
                    .foregroundStyle(selected ? Color.black.opacity(0.6) : Color.intent.mutedForeground)
                    .padding(.top, 4)
                Text(o.sub).font(.intent(12))
                    .foregroundStyle(selected ? Color.black.opacity(0.6) : Color.intent.mutedForeground)
            }
            .foregroundStyle(selected ? Color.black : Color.intent.foreground)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DashboardSurfaceButtonStyle(fill: selected ? .white : Color.intent.secondary,
                                                 pressed: selected ? .white : Color.intent.accent))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func capsLabel(_ text: String) -> some View {
        Text(text).font(.intent(11)).tracking(1.32).textCase(.uppercase).foregroundStyle(Color.intent.mutedForeground)
    }

    private func errorText(_ text: String) -> some View {
        Text(text).font(.intent(12, .medium)).foregroundStyle(Color.intent.destructive)
    }

    private func pillField(_ placeholder: String, text: Binding<String>, unit: String, fill: Color = Color.intent.secondary,
                           error: Bool = false, decimal: Bool = false, height: CGFloat = 48) -> some View {
        HStack(spacing: 6) {
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color.intent.mutedForeground.opacity(0.6)))
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .font(.intent(20, .light))
                .monospacedDigit()
                .foregroundStyle(Color.intent.foreground)
                .onChange(of: text.wrappedValue) { _, v in
                    if decimal, v.contains(",") { text.wrappedValue = v.replacingOccurrences(of: ",", with: ".") }
                }
            Text(unit).font(.intent(12)).foregroundStyle(Color.intent.mutedForeground).fixedSize()
        }
        .padding(.horizontal, 20)
        .frame(height: height)
        .background(Capsule().fill(fill))
        .overlay { if error { Capsule().strokeBorder(Color.intent.destructive, lineWidth: 1) } }
    }

    private func save() async {
        guard goalError == nil, !hasRangeError else { return }
        let cal = Int(calories.trimmingCharacters(in: .whitespaces))
        let stp = Int(steps.trimmingCharacters(in: .whitespaces))
        let min = Int(cardioMinutes.trimmingCharacters(in: .whitespaces))
        let days = IndependentTargets.orderCardioDays(cardioDays)
        let gw = phase == .maintenance ? nil : Double(goalWeight.trimmingCharacters(in: .whitespaces))
        // NOTE: the generated client omits nil fields rather than sending null, so a
        // cleared target (blank field, maintenance's goal weight) is not cleared on the
        // server the way the web's `null` clears it. See the Dashboard report.
        let update = IntentSchemas.UserProfileUpdate(
            goal: IndependentTargets.phaseOption(phase).goal,
            goalWeight: gw,
            dailyCalorieTarget: cal,
            dailyStepTarget: stp,
            cardioDays: days,
            cardioMinutes: !days.isEmpty ? min : nil)
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        do {
            _ = try await client.api.updateProfile(body: .json(update)).ok.body.json
        } catch {
            saveFailed = true
            return
        }
        // Mirror the saved draft locally (the mock backend is stateless), then
        // refresh the progress tracker the goal weight feeds.
        if var p = model.profile {
            p.goal = update.goal ?? p.goal
            p.goalWeight = gw
            p.dailyCalorieTarget = cal
            p.dailyStepTarget = stp
            p.cardioDays = days
            p.cardioMinutes = update.cardioMinutes
            model.profile = p
        }
        if let goal = try? await client.api.getGoalProgress().ok.body.json { model.goal = goal }
        editing = false
    }
}

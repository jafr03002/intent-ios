import IntentCore
import IntentDesign
import SwiftUI

/// The stepped form (onboarding.tsx's "form" phase), direction A "Stacked cards":
/// a thin progress bar, a caps "Step N of M", one question per screen, an outlined
/// Back pill and a white Continue pill.
struct OnboardingFormView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Step \(model.step + 1) of \(model.totalSteps)")
                            .intentText(.eyebrow)
                            .foregroundStyle(Color.intent.mutedForeground)
                            .padding(.bottom, 12)
                            .opacity(model.hasStarted ? 1 : 0)
                        stepContent
                            .id(model.currentStep)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 12)),
                                                    removal: .opacity.combined(with: .offset(x: -12))))
                        footer
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 48)
                    .frame(minHeight: geo.size.height, alignment: .leading) // centred vertically, like justify-center
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Color.intent.background.ignoresSafeArea())
        .foregroundStyle(Color.intent.foreground)
        .animation(.easeOut(duration: 0.2), value: model.step)
        .sheet(isPresented: $model.showGoalWeight) {
            OnboardingGoalWeightSheet(model: model)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.intent.secondary)
                Capsule().fill(Color.white).frame(width: geo.size.width * model.progress)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .animation(.easeOut(duration: 0.3), value: model.progress)
    }

    @ViewBuilder private var stepContent: some View {
        switch model.currentStep {
        case .mode: modeStep
        case .name: nameStep
        case .bodyStats: bodyStatsStep
        case .goal: goalStep
        case .experience: experienceStep
        case .activity: activityStep
        case .trainingDays: trainingDaysStep
        case .preferredRestDays: restDaysStep
        case .equipment: equipmentStep
        case .details: detailsStep
        case .priorityMuscles: musclesStep
        case .targets: targetsStep
        case .review: reviewStep
        }
    }

    @ViewBuilder private var footer: some View {
        if !model.isLastStep {
            HStack(spacing: 10) {
                if model.step > 0 {
                    Button { model.back() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium))
                            Text("Back")
                        }
                    }
                    .buttonStyle(.intentOutline)
                    .fixedSize(horizontal: true, vertical: false)
                }
                Button { model.next() } label: {
                    HStack(spacing: 8) {
                        Text("Continue")
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.intentPrimary)
                .disabled(!model.canAdvance)
            }
            .padding(.top, 40)
        } else if model.step > 0 {
            Button { model.back() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                    Text("Back").intentText(.eyebrow)
                }
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
        }
    }

    private func header(_ title: String, _ lede: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).onboardingTitle()
            Text(lede).onboardingLede()
        }
    }

    // MARK: Steps

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("How do you want to train?", "Choose your mode - you can switch later in Settings.")
            VStack(spacing: IntentSpacing.stack) {
                ForEach(OnboardingOptions.modes, id: \.value) { option in
                    OnboardingChoiceCard(title: option.label, sub: option.sub, selected: model.form.mode == option.value,
                                         systemImage: option.value == "ai" ? "brain" : "person") {
                        model.form.mode = option.value
                    }
                }
            }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("What should we call you?", "Optional - you can change this later in Settings.")
            OnboardingPillField(placeholder: "Your name", text: $model.form.name, maxLength: FieldLimits.maxProfileName)
        }
    }

    private var bodyStatsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Body stats", "Optional - you can change this later in Settings.")
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingLabel(text: "Age")
                    OnboardingPillField(placeholder: "e.g. 28", text: $model.form.age, invalid: model.form.ageError != nil,
                                        keyboard: .numberPad)
                    if let error = model.form.ageError { OnboardingErrorText(text: error) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingLabel(text: "Weight")
                    HStack(spacing: 8) {
                        OnboardingPillField(placeholder: "e.g. 80", text: $model.form.weight,
                                            invalid: model.form.weightError != nil, keyboard: .decimalPad)
                        OnboardingUnitToggle(unit: $model.form.weightUnit)
                    }
                    if let error = model.form.weightError { OnboardingErrorText(text: error) }
                }
            }
        }
    }

    private var goalStep: some View {
        let goalWeightError = model.form.goalWeightError
        return VStack(alignment: .leading, spacing: 0) {
            header("What's your main goal?", model.form.mode == "ai"
                   ? "Shapes your program and targets. Every option is built around building or keeping muscle."
                   : "Sets the target your dashboard tracks against. Every option is built around building or keeping muscle.")
            VStack(spacing: IntentSpacing.stack) {
                ForEach(OnboardingOptions.goals, id: \.value) { goal in
                    let selected = model.form.goal == goal.value
                    OnboardingChoiceCard(title: goal.label, sub: goal.sub, selected: selected,
                                         action: { model.selectGoal(goal.value) }) {
                        if selected && OnboardingOptions.weightGoals.contains(goal.value) {
                            HStack(spacing: 8) {
                                Text("Goal weight:").foregroundStyle(Color.black.opacity(0.6))
                                Text(model.form.goalWeight.isEmpty ? "Not set" : "\(model.form.goalWeight) \(model.form.weightUnit)")
                                    .font(.intent(13, .medium))
                                    .foregroundStyle(goalWeightError != nil ? Color.intent.destructive : Color.black)
                                Text("Edit").underline().foregroundStyle(Color.black)
                                    .onTapGesture { model.editGoalWeight() }
                                    .accessibilityAddTraits(.isButton)
                            }
                            .font(.intent(13))
                            .padding(.top, 10)
                        }
                    }
                }
            }
            if let goalWeightError {
                Text(goalWeightError).font(.intent(13, .medium)).foregroundStyle(Color.intent.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
    }

    private var experienceStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Your experience level", "Honest answers lead to better programs.")
            VStack(spacing: IntentSpacing.stack) {
                ForEach(OnboardingOptions.experience, id: \.value) { e in
                    OnboardingChoiceCard(title: e.label, sub: e.sub, selected: model.form.experience == e.value) {
                        model.form.experience = e.value
                    }
                }
            }
        }
    }

    private var activityStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("How active are your days?", "Outside of training - this tells your coach how much you recover and burn.")
            VStack(spacing: IntentSpacing.stack) {
                ForEach(OnboardingOptions.activity, id: \.value) { a in
                    OnboardingChoiceCard(title: a.label, sub: a.sub, selected: model.form.activityLevel == a.value) {
                        model.form.toggleActivity(a.value)
                    }
                }
            }
            OnboardingNotice(text: "Not sure? Your phone's built-in step tracker (Apple Health, Google Fit, Samsung Health) shows your daily average.")
                .padding(.top, 16)
        }
    }

    private var trainingDaysStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Training days per week", "How many days can you commit to?")
            HStack(alignment: .lastTextBaseline) {
                Text("\(model.form.trainingDays)")
                    .font(.intent(88, .light))
                    .tracking(-3.5)
                    .contentTransition(.numericText())
                Spacer()
                Text("days / week").intentText(.eyebrow).foregroundStyle(Color.intent.mutedForeground)
            }
            OnboardingDaySlider(value: $model.form.trainingDays, range: OnboardingOptions.trainingDayRange)
                .padding(.top, 24).padding(.bottom, 12)
            HStack {
                ForEach(Array(OnboardingOptions.trainingDayRange), id: \.self) { n in
                    Text("\(n)")
                    if n != OnboardingOptions.trainingDayRange.upperBound { Spacer() }
                }
            }
            .font(.intent(12))
            .foregroundStyle(Color.intent.mutedForeground)
            .padding(.horizontal, 6)
        }
    }

    private var restDaysStep: some View {
        let f = model.form
        return VStack(alignment: .leading, spacing: 0) {
            header("Any preferred rest days?",
                   "You picked \(f.trainingDays) training days - choose the days you'd like to keep free. Optional.")
            OnboardingWrap {
                ForEach(OnboardingOptions.weekdays, id: \.value) { d in
                    let selected = f.preferredRestDays.contains(d.value)
                    OnboardingChip(title: d.label, selected: selected, invalid: selected && f.tooManyPreferredRestDays) {
                        model.form.togglePreferredRestDay(d.value)
                    }
                }
            }
            .padding(.bottom, 16)
            Group {
                if f.tooManyPreferredRestDays {
                    Text("Too many rest days to program around your \(f.trainingDays) training days - remove one to continue.")
                        .font(.intent(12.5, .medium)).foregroundStyle(Color.intent.destructive)
                } else if f.preferredRestDays.count == f.maxPreferredRestDays {
                    Text("You've picked the most rest days we can plan around your \(f.trainingDays) training days.")
                        .font(.intent(12.5, .medium)).foregroundStyle(Color.intent.foreground)
                } else if f.preferredRestDays.isEmpty {
                    Text("No preference - your coach schedules your days.")
                        .font(.intent(12.5)).foregroundStyle(Color.intent.mutedForeground)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var equipmentStep: some View {
        let f = model.form
        return VStack(alignment: .leading, spacing: 0) {
            header("Available equipment",
                   "Select everything you have access to, or just \"Full gym\" if that covers it - it's a single choice that can't be combined with the others.")
            OnboardingWrap {
                ForEach(OnboardingOptions.equipment, id: \.self) { item in
                    OnboardingChip(title: item, selected: f.equipment.contains(item)) { model.form.toggleEquipment(item) }
                }
            }
            .padding(.bottom, 16)
            if f.equipment.contains("Full gym") {
                caption("Full gym selected - covers everything")
            } else if !f.equipment.isEmpty {
                caption("\(f.equipment.count) selected")
            }
        }
    }

    private var detailsStep: some View {
        let f = model.form
        return VStack(alignment: .leading, spacing: 0) {
            header("A bit more for your AI coach", "Optional - helps tailor your program.")
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingLabel(text: "Sex", optional: true)
                    HStack(spacing: 8) {
                        ForEach(["Male", "Female"], id: \.self) { s in
                            OnboardingChip(title: s, selected: f.sex == s.lowercased(), height: 52) {
                                model.form.toggleSex(s.lowercased())
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingLabel(text: "Injuries or limitations")
                    TextField("", text: Binding(get: { model.form.injuries }, set: { model.form.setInjuries($0) }),
                              prompt: Text("e.g. bad lower back, knee pain").foregroundStyle(Color.intent.mutedForeground.opacity(0.6)),
                              axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .font(.intent(16))
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous).fill(Color.intent.card))
                }
                if !f.injuries.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingLabel(text: "How bad is it?", optional: true)
                        VStack(spacing: IntentSpacing.stack) {
                            ForEach(OnboardingOptions.injurySeverity, id: \.value) { s in
                                OnboardingChoiceCard(title: s.label, sub: s.sub, selected: f.injurySeverity == s.value) {
                                    model.form.toggleInjurySeverity(s.value)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var musclesStep: some View {
        let f = model.form
        return VStack(alignment: .leading, spacing: 0) {
            header("Priority muscle groups", "Pick up to 3. Extra volume goes here.")
            OnboardingWrap {
                ForEach(OnboardingOptions.muscles, id: \.self) { m in
                    OnboardingChip(title: m, selected: f.priorityMuscles.contains(m)) { model.form.toggleMuscle(m) }
                }
            }
            .padding(.bottom, 16)
            caption(f.priorityMuscles.contains(OnboardingOptions.noPreference)
                    ? "No preference selected" : "\(f.selectedMuscleCount) / 3 selected")
        }
    }

    private var targetsStep: some View {
        let f = model.form
        let hasCardio = !f.cardioDays.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            header("Set your targets",
                   "What you're aiming for day to day. We've suggested a starting point - adjust anything, or skip and set it later.")
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingLabel(text: "Calorie target")
                    OnboardingPillField(placeholder: "e.g. 2200", text: $model.form.dailyCalorieTarget,
                                        invalid: f.calorieTargetError != nil, keyboard: .numberPad, suffix: "kcal / day")
                    if let e = f.calorieTargetError { OnboardingErrorText(text: e) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingLabel(text: "Step target")
                    OnboardingPillField(placeholder: "e.g. 8000", text: $model.form.dailyStepTarget,
                                        invalid: f.stepTargetError != nil, keyboard: .numberPad, suffix: "steps / day")
                    if let e = f.stepTargetError { OnboardingErrorText(text: e) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingLabel(text: "Cardio", optional: true)
                    OnboardingWrap {
                        ForEach(IndependentTargets.cardioDays, id: \.self) { d in
                            OnboardingChip(title: d, selected: f.cardioDays.contains(d)) { model.form.toggleCardioDay(d) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Text("Minutes each day:").font(.intent(13)).foregroundStyle(Color.intent.mutedForeground)
                            OnboardingPillField(placeholder: "e.g. 25", text: $model.form.cardioMinutes,
                                                invalid: f.cardioMinutesError != nil, keyboard: .numberPad, suffix: "min")
                                .frame(width: 128)
                                .disabled(!hasCardio)
                        }
                        if let e = f.cardioMinutesError { OnboardingErrorText(text: e) }
                    }
                    .padding(.top, 12)
                    .opacity(hasCardio ? 1 : 0.4)
                }
            }
            OnboardingNotice(text: "You can change these anytime from your dashboard.").padding(.top, 24)
        }
    }

    private var reviewStep: some View {
        let isAI = model.form.mode == "ai"
        return VStack(alignment: .leading, spacing: 0) {
            header(isAI ? "Ready to build your program" : "You're all set",
                   isAI ? "Here's what your AI coach will use." : "Your profile is ready. Head to My Program to build your first program.")
            VStack(spacing: 0) {
                let rows = model.form.reviewRows
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack(alignment: .top, spacing: 16) {
                        Text(row.label).foregroundStyle(Color.intent.mutedForeground).fixedSize()
                        Text(row.value).foregroundStyle(Color.intent.foreground)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.intent(14))
                    .padding(.vertical, 14)
                    .padding(.trailing, 20)
                    .overlay(alignment: .bottom) { if i < rows.count - 1 { IntentDivider() } }
                    .padding(.leading, 20)
                }
            }
            .background(RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous).fill(Color.intent.card))
            .padding(.bottom, 24)

            if model.createError || model.job.isError {
                Text("Something went wrong. Please try again."
                     + (model.createError ? model.createErrorDetail.map { "\n\($0)" } ?? "" : ""))
                    .font(.intent(12.5)).foregroundStyle(Color.intent.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: IntentRadius.notice, style: .continuous)
                        .fill(Color.intent.destructive.opacity(0.1)))
                    .padding(.bottom, 16)
            }

            if isAI {
                VStack(spacing: 10) {
                    Button { Task { await model.finish(generateNow: true) } } label: {
                        pendingLabel(model.isPending && model.finishAction == .generate,
                                     busy: model.createPending ? "Saving profile..." : "Building your program...",
                                     idle: "Generate program")
                    }
                    .buttonStyle(.intentPrimary)
                    Button { Task { await model.finish(generateNow: false) } } label: {
                        pendingLabel(model.isPending && model.finishAction == .later, busy: "Saving profile...",
                                     idle: "Generate program later")
                    }
                    .buttonStyle(.intentOutline)
                    Text("You can generate your program any time from My Program.")
                        .font(.intent(12.5)).foregroundStyle(Color.intent.mutedForeground)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .disabled(model.isPending)
            } else {
                Button { Task { await model.finish(generateNow: false) } } label: {
                    pendingLabel(model.isPending, busy: "Saving profile...", idle: "Get started")
                }
                .buttonStyle(.intentPrimary)
                .disabled(model.isPending)
            }
        }
    }

    @ViewBuilder private func pendingLabel(_ isBusy: Bool, busy busyText: String, idle: String) -> some View {
        if isBusy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Color.intent.mutedForeground)
                Text(busyText)
            }
        } else {
            Text(idle)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.intent(12.5)).foregroundStyle(Color.intent.mutedForeground)
    }
}

/// The "What weight do you want to reach?" bottom sheet.
struct OnboardingGoalWeightSheet: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What weight do you want to reach?")
                .font(.intent(22)).tracking(-0.22)
                .fixedSize(horizontal: false, vertical: true)
            Text("Saved as your long-term goal weight\(model.form.weight.isEmpty ? "" : " (now: \(model.form.weight) \(model.form.weightUnit))"). You can skip this.")
                .intentText(.lede).foregroundStyle(Color.intent.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 8) {
                OnboardingPillField(placeholder: "Target \(model.form.weightUnit)",
                                    text: Binding(get: { model.goalWeightDraft },
                                                  set: { model.goalWeightDraft = $0; model.goalWeightSaveError = nil }),
                                    invalid: model.goalWeightSaveError != nil, keyboard: .decimalPad,
                                    fill: Color.intent.secondary, onSubmit: { model.saveGoalWeight() })
                OnboardingUnitToggle(unit: $model.form.weightUnit, fill: Color.intent.secondary,
                                     onChange: { model.goalWeightSaveError = nil })
            }
            .padding(.top, 20)
            if let error = model.goalWeightSaveError {
                Text(error).font(.intent(13, .medium)).foregroundStyle(Color.intent.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            GeometryReader { geo in
                HStack(spacing: 10) {
                    Button("Skip") { model.skipGoalWeight() }
                        .buttonStyle(.intentOutline)
                        .frame(width: (geo.size.width - 10) / 2.4)
                    Button("Save target") { model.saveGoalWeight() }
                        .buttonStyle(.intentPrimary)
                }
            }
            .frame(height: IntentMetrics.controlHeight)
            .padding(.top, 24)
        }
        .foregroundStyle(Color.intent.foreground)
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(model.goalWeightSaveError == nil ? 300 : 360)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.intent.card)
        .presentationCornerRadius(30)
    }
}

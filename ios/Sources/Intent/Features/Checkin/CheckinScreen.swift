import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// The weekly check-in (web: pages/checkin.tsx): the AI coach's weekly review. One
/// question per screen in onboarding's stacked-card kit, then the coach's message.
/// Pushed from the dashboard banner; runs full screen and carries its own close button.
///
/// Closed during calibration and until a week after the calibration review
/// (`Calibration.checkinGate`); the server refuses a submission then too. The
/// calibration review itself is a separate readiness check with no UI yet.
struct CheckinScreen: View {
    private let debug: CheckinDebug

    init(debug: CheckinDebug = .none) {
        self.debug = debug
    }

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The tab shell's launcher, for "See updated program" (absent in debug hosts).
    @Environment(WorkoutLauncher.self) private var launcher: WorkoutLauncher?
    @State private var model: CheckinModel?

    var body: some View {
        ZStack {
            Color.intent.background.ignoresSafeArea()
            if let model {
                CheckinContent(model: model, close: close, seeProgram: seeProgram)
            }
        }
        .foregroundStyle(Color.intent.foreground)
        .toolbar(.hidden, for: .navigationBar)
        .hidesIntentTabBar() // the web hides the bottom nav on the check-in
        .task { await start() }
        .onChange(of: scenePhase) { _, phase in
            // Timers freeze while the phone is locked: ask the moment it's back.
            if phase == .active { model?.job.wake() }
        }
    }

    private func close() { dismiss() }

    private func seeProgram() {
        dismiss()
        launcher?.selectTab?(.program)
    }

    private func start() async {
        guard model == nil else { return }
        var client = services.api
        if services.isMock, let scenario = debug.pinnedScenario {
            client = IntentAPIClient(environment: .production, transport: FixtureTransport(scenario: scenario))
        }
        let job = CheckinJobRunner(
            client: client,
            pollInterval: debug == .result ? .milliseconds(300) : AiJobPolicy.pollInterval,
            // Mock mode keeps no job between launches, so one CI screenshot can't
            // leave a review running for the next.
            defaults: services.isMock ? nil : .standard
        )
        let model = CheckinModel(job: job)
        self.model = model
        Task { await model.resumeIfNeeded() }
        await model.load(client)
        await debug.apply(to: model)
    }
}

// MARK: - Content

private struct CheckinContent: View {
    @Bindable var model: CheckinModel
    let close: () -> Void
    let seeProgram: () -> Void

    var body: some View {
        if let message = model.resultMessage {
            CheckinResultView(message: message, seeProgram: seeProgram)
        } else if model.resuming {
            VStack(spacing: 12) {
                ProgressView().tint(Color.intent.mutedForeground)
                Text("Your AI coach is reviewing your week...").font(.intent(14))
            }
            .foregroundStyle(Color.intent.mutedForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let gate = model.gate, !gate.isOpen {
            CheckinClosedView(gate: gate, close: close)
        } else {
            form
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            HStack {
                CheckinCloseButton(action: close)
                Spacer()
                // Progress is the caps count only - no bar (TrainientAppDesign.md).
                Text("\(model.safeStep + 1) of \(model.steps.count)")
                    .intentText(.eyebrow)
                    .foregroundStyle(Color.intent.mutedForeground)
            }
            .padding(.horizontal, IntentSpacing.gutter)
            .padding(.top, 16)

            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        question
                            .id(model.currentStep)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 12)),
                                                    removal: .opacity.combined(with: .offset(x: -12))))

                        if let error = model.job.error {
                            Text(error)
                                .font(.intent(13, .medium))
                                .foregroundStyle(Color.intent.destructive)
                                .padding(.leading, 4)
                                .padding(.top, 24)
                        }

                        dock.padding(.top, 40)
                    }
                    .padding(.horizontal, IntentSpacing.gutter)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    private var dock: some View {
        HStack(spacing: 12) {
            if model.safeStep > 0 {
                Button { go(to: model.safeStep - 1) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium))
                        Text("Back")
                    }
                }
                .buttonStyle(.intentOutline)
                .fixedSize(horizontal: true, vertical: false)
            }
            if model.isLastStep {
                Button { Task { await model.submit() } } label: {
                    if model.job.isPending {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(Color.intent.mutedForeground)
                            Text("Reviewing your week...").truncationMode(.tail)
                        }
                    } else {
                        Text("Submit check-in")
                    }
                }
                .buttonStyle(.intentPrimary)
                .disabled(model.job.isPending)
            } else {
                Button("Continue") { go(to: model.safeStep + 1) }
                    .buttonStyle(.intentPrimary)
                    .disabled(!model.canAdvance)
            }
        }
    }

    private func go(to step: Int) {
        withAnimation(.easeOut(duration: 0.2)) { model.step = step }
    }

    @ViewBuilder private var question: some View {
        switch model.currentStep {
        case .energy:
            CheckinQuestion("How was your energy this week?") {
                CheckinScale(value: $model.answers.energy, labels: CheckinFlow.energyLabels)
            }
        case .sleep:
            CheckinQuestion("How was your sleep quality?") {
                CheckinScale(value: $model.answers.sleep, labels: CheckinFlow.sleepLabels)
            }
        case .sleepDecline:
            CheckinQuestion("Was there a decline in sleep duration or quality?",
                            hint: "If so, what caused it? Leave blank if nothing changed.") {
                CheckinTextArea(text: $model.answers.sleepDecline, placeholder: "Late nights, stress, travel...")
            }
        case .soreness:
            CheckinQuestion("How sore were you going into sessions?",
                            hint: "Your coach reads this as the fatigue signal when deciding whether to add or pull back volume.") {
                HStack(spacing: IntentSpacing.stack) {
                    ForEach(CheckinFlow.sorenessOptions, id: \.self) { option in
                        CheckinChoiceCard(option, isSelected: model.answers.soreness == option.lowercased(),
                                          font: .intent(15, .medium), centered: true, horizontalPadding: 8) {
                            model.answers.soreness = option.lowercased()
                        }
                    }
                }
            }
        case .sessions:
            CheckinQuestion("Your training week") {
                CheckinSessionsSummary(isLoading: model.adherenceLoading, adherence: model.adherence)
            }
        case .missedReason:
            if let adherence = model.adherence {
                CheckinQuestion(CheckinFlow.missedReasonTitle(missingDayLabels: adherence.missingDays.map(\.label)),
                                hint: "If you trained it and just didn't log it, say so - your coach won't cut your training for a logging gap.") {
                    VStack(spacing: IntentSpacing.stack) {
                        ForEach(CheckinFlow.missedReasons, id: \.value) { reason in
                            CheckinChoiceCard(reason.label, isSelected: model.answers.missedReason == reason.value,
                                              font: .intent(15)) {
                                model.answers.missedReason = reason.value
                            }
                        }
                    }
                }
            }
        case .exerciseIssues:
            CheckinQuestion("Any issues with exercises?",
                            hint: "Mind-muscle connection, joint or muscle pain - name the exercise and what you felt.") {
                CheckinTextArea(text: $model.answers.exerciseIssues, placeholder: "Which exercise, and what you felt...")
            }
        case .hunger:
            CheckinQuestion("How was your hunger and appetite?") {
                CheckinScale(value: $model.answers.hungerAppetite, labels: CheckinFlow.hungerLabels)
            }
        case .offDay:
            CheckinQuestion("Any off days where you deviated from your calories and didn't log it?",
                            hint: "Be honest - if the data isn't reliable, your coach won't change your calories off it.") {
                HStack(spacing: IntentSpacing.stack) {
                    ForEach([false, true], id: \.self) { value in
                        CheckinChoiceCard(value ? "Yes" : "No", isSelected: model.answers.offDayDeviation == value,
                                          font: .intent(16, .medium), centered: true) {
                            model.answers.offDayDeviation = value
                        }
                    }
                }
            }
        case .digestion:
            CheckinQuestion("Any issues with digestion?") {
                CheckinTextArea(text: $model.answers.digestionIssues, placeholder: "Bloating, discomfort...")
            }
        case .wentWell:
            CheckinQuestion("What went well this week?") {
                CheckinTextArea(text: $model.answers.wentWell, placeholder: "Wins worth repeating...")
            }
        case .didntGoWell:
            CheckinQuestion("What didn't go well, and can be improved?") {
                CheckinTextArea(text: $model.answers.didntGoWell, placeholder: "What you'd like your coach to help resolve...")
            }
        case .notes:
            CheckinQuestion("Anything else for your coach?") {
                CheckinTextArea(text: $model.answers.notes, placeholder: "Anything else that affected your training...")
            }
        }
    }
}

// MARK: - Result / closed

private struct CheckinResultView: View {
    let message: String
    let seeProgram: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IntentSpacing.section) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Check-in submitted").intentText(.screenTitle)
                    Text("Your AI coach has reviewed your week.")
                        .intentText(.lede)
                        .foregroundStyle(Color.intent.mutedForeground)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Coach message")
                        .intentText(.eyebrow)
                        .foregroundStyle(Color.intent.sessionsCyan)
                    Text(message)
                        .font(.intent(15))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .intentSurface(radius: IntentRadius.groupedList)

                Button(action: seeProgram) {
                    HStack(spacing: 8) {
                        Text("See updated program")
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.intentPrimary)
            }
            .padding(IntentSpacing.gutter)
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
        .transition(.opacity.combined(with: .offset(y: 12)))
    }
}

private struct CheckinClosedView: View {
    let gate: CheckinGate
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The web puts this close button on the right (the form's is on the left).
            HStack {
                Spacer()
                CheckinCloseButton(action: close)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Not yet").intentText(.screenTitle)
                Text(lede)
                    .intentText(.lede)
                    .foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(IntentSpacing.gutter)
    }

    private var lede: String {
        if case .closedUntil(let opensAt) = gate {
            // `toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" })`.
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
            return "Your first check-in opens on \(f.string(from: opensAt)), a week after your calibration review."
        }
        return "There are no check-ins during calibration. Your weekly check-ins start a week after your calibration review."
    }
}

// MARK: - Form kit

private struct CheckinCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color.intent.mutedForeground)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.intent.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close check-in")
    }
}

/// A question screen: thin title, optional muted hint, then the input.
private struct CheckinQuestion<Content: View>: View {
    let title: String
    let hint: String?
    let content: Content

    init(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .intentText(.screenTitle)
                .fixedSize(horizontal: false, vertical: true)
            if let hint {
                Text(hint)
                    .intentText(.lede)
                    .foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            content.padding(.top, 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Five circles, each carrying its own meaning - filled white once picked.
private struct CheckinScale: View {
    @Binding var value: Int
    let labels: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                let n = i + 1
                let selected = value == n
                Button { value = n } label: {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(selected ? Color.white : Color.intent.card)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 60)
                            .overlay {
                                Text("\(n)")
                                    .font(.intent(24, .light))
                                    .monospacedDigit()
                                    .foregroundStyle(selected ? Color.black : Color.intent.mutedForeground)
                            }
                        Text(label)
                            .font(.intent(11))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(selected ? Color.intent.foreground : Color.intent.mutedForeground)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(n) - \(label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.15), value: value)
    }
}

/// `optionCardClass`: grey at rest, white with black text once picked.
private struct CheckinChoiceCard: View {
    let title: String
    let isSelected: Bool
    let font: Font
    let centered: Bool
    let horizontalPadding: CGFloat
    let action: () -> Void

    init(_ title: String, isSelected: Bool, font: Font, centered: Bool = false,
         horizontalPadding: CGFloat = IntentSpacing.rowInset, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.font = font
        self.centered = centered
        self.horizontalPadding = horizontalPadding
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .multilineTextAlignment(centered ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, IntentSpacing.optionVertical)
                .foregroundStyle(isSelected ? Color.black : Color.intent.foreground)
                .background(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous)
                    .fill(isSelected ? Color.white : Color.intent.card))
                .contentShape(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The free-text answer: a four-line `rounded-3xl bg-card` box.
private struct CheckinTextArea: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text,
                  prompt: Text(placeholder).foregroundStyle(Color.intent.mutedForeground.opacity(0.6)),
                  axis: .vertical)
            .font(.intent(16))
            .lineLimit(4, reservesSpace: true)
            .focused($focused)
            .tint(Color.intent.foreground)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous).fill(Color.intent.card))
            .overlay {
                RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous)
                    .strokeBorder(Color.intent.foreground.opacity(focused ? 0.4 : 0), lineWidth: 1)
            }
    }
}

/// Read-only: adherence is derived from what was logged, not asked for. The server
/// recomputes it on submit, so this previews what the coach sees.
private struct CheckinSessionsSummary: View {
    let isLoading: Bool
    let adherence: IntentSchemas.SessionAdherence?

    var body: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Color.intent.mutedForeground)
                Text("Checking what you logged...")
            }
            .font(.intent(14))
            .foregroundStyle(Color.intent.mutedForeground)
        } else if let a = adherence {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(a.loggedSessions)\(Text(" / \(a.plannedSessions)").foregroundStyle(Color.intent.mutedForeground))")
                        .font(.intent(34, .light))
                        .tracking(-0.68)
                        .monospacedDigit()
                    Text("sessions logged")
                        .intentText(.eyebrow)
                        .foregroundStyle(Color.intent.mutedForeground)
                }
                .padding(.bottom, 12)

                // Inset grouped list, as on the program page.
                VStack(spacing: 0) {
                    let rows = a.loggedDays.map { (day: $0, logged: true) } + a.missingDays.map { (day: $0, logged: false) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        SummaryRow(label: row.day.label,
                                   trailing: row.logged ? (row.day.date ?? "") : "not logged",
                                   logged: row.logged, isLast: i == rows.count - 1)
                    }
                }
                .background(Color.intent.card)
                .clipShape(RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous))

                if let extra = CheckinFlow.extraSessionsLine(a.extraSessions) {
                    Text(extra)
                        .font(.intent(12.5))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .padding(.top, 12)
                        .padding(.leading, 4)
                }
            }
        } else {
            Text("We couldn't read your training week - your coach will work from your answers alone.")
                .font(.intent(14))
                .foregroundStyle(Color.intent.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct SummaryRow: View {
        let label: String
        let trailing: String
        let logged: Bool
        let isLast: Bool

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: logged ? "checkmark" : "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(logged ? Color.intent.sessionsCyan : Color.intent.mutedForeground)
                    .frame(width: 16)
                Text(label)
                    .font(.intent(15))
                    .foregroundStyle(logged ? Color.intent.foreground : Color.intent.mutedForeground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(trailing)
                    .font(.intent(13))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize()
            }
            .padding(.vertical, 15)
            .padding(.trailing, 20)
            .overlay(alignment: .bottom) { if !isLast { IntentDivider() } }
            .padding(.leading, 20)
        }
    }
}

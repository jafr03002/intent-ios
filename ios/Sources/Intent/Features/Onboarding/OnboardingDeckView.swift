import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// The post-generation deck (PresentationDeck.tsx, direction C "Coach's letter"):
/// letter -> program -> journey -> volume -> sessions -> "Happy with it?". The last
/// page's "Tweak something" opens the feedback sheet that rebuilds the program.
struct OnboardingDeckView: View {
    typealias Page = PresentationDeck.Page

    let program: IntentCore.Program
    let goal: String
    let weightUnit: String
    let name: String?
    let priorityMuscles: [String]
    let showRegenerateNudge: Bool
    let error: Bool
    let onSatisfied: () -> Void
    let onSubmitFeedback: (OnboardingFeedback) -> Void

    @State private var page: Int
    @State private var tweaking: Bool

    init(program: IntentCore.Program, goal: String, weightUnit: String, name: String?, priorityMuscles: [String],
         showRegenerateNudge: Bool, error: Bool, initialPage: Int = 0, initialTweaking: Bool = false,
         onSatisfied: @escaping () -> Void, onSubmitFeedback: @escaping (OnboardingFeedback) -> Void) {
        self.program = program; self.goal = goal; self.weightUnit = weightUnit; self.name = name
        self.priorityMuscles = priorityMuscles; self.showRegenerateNudge = showRegenerateNudge; self.error = error
        self.onSatisfied = onSatisfied; self.onSubmitFeedback = onSubmitFeedback
        _page = State(initialValue: initialPage)
        _tweaking = State(initialValue: initialTweaking)
    }

    private var pages: [Page] { Page.allCases }
    private var current: Page { pages[page] }
    private var isLast: Bool { page == pages.count - 1 }
    private var days: [ProgramDay] { program.days }
    private var focus: [String] { PresentationDeck.focus(priorityMuscles) }
    private var focusText: String { PresentationDeck.joinWithAnd(focus.map(PresentationDeck.muscleKey)) }
    private var goalWeightText: String? {
        program.longTermGoalWeight.map { "\(OnboardingDeckFormat.number($0)) \(weightUnit)" }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.intent.background.ignoresSafeArea()
            OnboardingLetterWash(bookend: current == .letter || current == .happy)
                .animation(.easeOut(duration: 0.22), value: current)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        OnboardingPageDots(count: pages.count, index: page) { page = $0 }
                    }
                    .padding(.top, 16)
                    pageContent
                        .id(current)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 20)),
                                                removal: .opacity.combined(with: .offset(x: -20))))
                        .padding(.top, 28)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 200)
            }
            .scrollIndicators(.hidden)
            .id(page) // each page starts at the top (window.scrollTo(0, 0))
        }
        .foregroundStyle(Color.intent.foreground)
        .animation(.easeOut(duration: 0.22), value: page)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingLetterDock(
                label: current == .letter ? "Show me" : isLast ? "Yes, let's go" : "Next",
                onNext: { if isLast { onSatisfied() } else { page = min(pages.count - 1, page + 1) } },
                onBack: page > 0 ? { page = max(0, page - 1) } : nil
            ) {
                if isLast {
                    HStack(spacing: 4) {
                        Text("Not quite?").foregroundStyle(Color.intent.mutedForeground)
                        Button { tweaking = true } label: {
                            Text("Tweak something").underline().foregroundStyle(Color.intent.foreground)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.intent(13))
                    .padding(.top, 14)
                }
            }
        }
        .sheet(isPresented: $tweaking) {
            OnboardingFeedbackSheet(currentTrainingDays: days.count, showRegenerateNudge: showRegenerateNudge) { feedback in
                tweaking = false
                onSubmitFeedback(feedback)
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch current {
        case .letter: letterPage
        case .program: programPage
        case .journey: journeyPage
        case .volume: volumePage
        case .sessions: sessionsPage
        case .happy: happyPage
        }
    }

    // MARK: Pages

    private var letterPage: some View {
        let longTerm = PresentationDeck.longTerm(goal: goal)
        var parts: [OnboardingSayPart] = [
            .fact("\(PresentationDeck.capitalise(PresentationDeck.numberWord(days.count))) days a week"),
            .plain(", \(PresentationDeck.splitText(program.splitType)). "),
        ]
        if let longTerm {
            parts += [.plain("You're heading into a "), .fact(longTerm + (goalWeightText.map { " toward \($0)" } ?? ""))]
        } else {
            parts += [.plain("You'll train at "), .fact("maintenance")]
        }
        parts += focus.isEmpty ? [.plain(".")] : [.plain(", with extra focus on your "), .fact(focusText), .plain(".")]
        return VStack(alignment: .leading, spacing: 0) {
            OnboardingSun(size: 48)
            OnboardingSay([.fact(name.map { "\($0), your plan is ready." } ?? "Your plan is ready.")], size: 32, lineHeight: 1.2)
                .padding(.top, 24)
            OnboardingSay(parts, size: 22, lineHeight: 1.38).padding(.top, 16)
        }
        .padding(.top, 64)
    }

    private var programPage: some View {
        let word = PresentationDeck.numberWord(days.count)
        return VStack(alignment: .leading, spacing: 0) {
            OnboardingPageHead(title: "Program", parts: focus.isEmpty
                ? [.plain("Built for the "), .fact("\(word) days"), .plain(" you have.")]
                : [.plain("Built around your "), .fact(focusText), .plain(", on the "), .fact("\(word) days"), .plain(" you have.")])
            Text(program.programName).font(.intent(19, .light)).foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 24)
            VStack(spacing: 8) {
                if !focus.isEmpty {
                    highlightCard(eyebrow: "Your focus",
                                  title: "\(PresentationDeck.capitalise(focusText)) come first",
                                  detail: "They get extra sets every week, so they grow ahead of the rest.")
                }
                ForEach(Array(PresentationDeck.highlights(program).enumerated()), id: \.offset) { _, h in
                    highlightCard(eyebrow: nil, title: h.title, detail: h.detail)
                }
            }
            .padding(.top, 12)
        }
    }

    private func highlightCard(eyebrow: String?, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(eyebrow).font(.intent(10)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Color.intent.sessionsCyan).padding(.bottom, 2)
            }
            Text(title).font(.intent(15)).foregroundStyle(Color.intent.foreground)
            Text(detail).font(.intent(12.5)).lineSpacing(3).foregroundStyle(Color.intent.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous).fill(Color.intent.card))
    }

    private var journeyPage: some View {
        let phases = PresentationDeck.timeline(goal: goal)
        let currentIndex = PresentationDeck.currentIndex(phases, shortTermPhase: program.shortTermPhase?.rawValue, goal: goal)
        var parts: [OnboardingSayPart] = [.plain("Start with "), .fact("a week of calibration"), .plain(", ")]
        switch goal {
        case "gain_weight":
            parts += goalWeightText.map { [.plain("then a "), .fact("bulk"), .plain(" all the way to "), .fact($0), .plain(".")] }
                ?? [.plain("then a "), .fact("bulk"), .plain(" to build size.")]
        case "lose_weight":
            parts += goalWeightText.map { [.plain("then "), .fact("step by step"), .plain(" down to "), .fact($0), .plain(".")] }
                ?? [.plain("then "), .fact("step by step"), .plain(" down.")]
        default:
            parts += [.plain("then "), .fact("steady training"), .plain(" at maintenance.")]
        }
        return VStack(alignment: .leading, spacing: 0) {
            OnboardingPageHead(title: "Your journey", parts: parts)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(phases.enumerated()), id: \.offset) { i, p in
                    OnboardingTimelineRow(phase: p, now: i == currentIndex)
                }
                if let goalWeightText, let week = PresentationDeck.goalWeek(goal) {
                    HStack(spacing: 14) {
                        Image(systemName: "flag")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(goalWeightText).font(.intent(30, .light)).tracking(-0.6)
                            Text("Goal · week \(week)").font(.intent(10.5)).tracking(1.26).textCase(.uppercase)
                                .foregroundStyle(Color.intent.mutedForeground)
                        }
                    }
                }
            }
            .padding(.top, 32)
        }
    }

    private var volumePage: some View {
        let volume = PresentationDeck.weeklyVolume(days)
        let total = volume.reduce(0) { $0 + $1.sets }
        let maxSets = max(1, volume.map(\.sets).max() ?? 1)
        let focusKeys = Set(focus.map(PresentationDeck.muscleKey))
        let week = PresentationDeck.week(program)
        return VStack(alignment: .leading, spacing: 0) {
            OnboardingPageHead(title: "Volume", parts: focus.isEmpty
                ? [.fact("\(total) hard sets"), .plain(" a week, spread across every muscle.")]
                : [.fact("\(total) hard sets"), .plain(" a week, with extra for your "), .fact(focusText), .plain(".")])
            VStack(spacing: 0) {
                ForEach(Array(volume.enumerated()), id: \.offset) { i, row in
                    let prioritised = focusKeys.contains(row.muscle)
                    HStack(spacing: 12) {
                        (Text(PresentationDeck.muscleLabel(row.muscle))
                            .foregroundStyle(prioritised ? Color.intent.foreground : Color.intent.foreground.opacity(0.8))
                         + Text(prioritised ? " ·" : "").foregroundStyle(Color.intent.sessionsCyan))
                            .font(.intent(13.5)).lineLimit(1)
                            .frame(width: 104, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.intent.card)
                                Capsule().fill(prioritised ? Color.white : Color.intent.mutedForeground)
                                    .frame(width: geo.size.width * CGFloat(row.sets) / CGFloat(maxSets))
                            }
                        }
                        .frame(height: 3)
                        Text("\(row.sets)").font(.intent(13)).foregroundStyle(Color.intent.mutedForeground)
                            .frame(width: 24, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { if i < volume.count - 1 { IntentDivider() } }
                }
            }
            .padding(.top, 20)

            Text("Your week").intentText(.eyebrow).foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 28).padding(.bottom, 10)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(ProgramScheduleReader.weekdayLabels, id: \.self) { wd in
                    Text(wd).font(.intent(10, .medium)).foregroundStyle(Color.intent.mutedForeground)
                }
                ForEach(0..<7, id: \.self) { i in
                    if let day = week[i] {
                        Text(day.label).font(.intent(9.5, .medium)).foregroundStyle(Color.intent.foreground)
                            .lineLimit(3).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                            .padding(.horizontal, 4).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.intent.card))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.intent.border, lineWidth: 1)
                            .frame(minHeight: 68)
                    }
                }
            }
            Text(PresentationDeck.isRealSchedule(program)
                 ? "\(days.count) training days a week, on the days you kept free."
                 : "\(days.count) training days a week, with rest spread between them.")
                .font(.intent(11)).foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 8)
        }
    }

    private var sessionsPage: some View {
        let duration = PresentationDeck.durationText(days)
        var parts: [OnboardingSayPart] = [.fact("\(PresentationDeck.capitalise(PresentationDeck.numberWord(days.count))) sessions")]
        parts += duration.map { [.plain(", about "), .fact($0), .plain(" each.")] } ?? [.plain(".")]
        return VStack(alignment: .leading, spacing: 0) {
            OnboardingPageHead(title: "Sessions", parts: parts)
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    OnboardingSessionRow(day: day, isLast: i == days.count - 1)
                }
            }
            .padding(.top, 20)
        }
    }

    private var happyPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingSun(size: 64)
            OnboardingSay([.fact("Happy with it?")], size: 32, lineHeight: 1.2).padding(.top, 24)
            OnboardingSay([.plain("You can change anything before you start. Once you're training, I'll adjust it from your real sessions.")],
                          size: 20, lineHeight: 1.4)
                .padding(.top, 16)
            if error {
                Text("Something went wrong rebuilding your program. Please try again.")
                    .font(.intent(13)).foregroundStyle(Color.intent.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: IntentRadius.notice, style: .continuous).fill(Color.intent.card))
                    .padding(.top, 24)
            }
        }
        .padding(.top, 64)
    }
}

enum OnboardingDeckFormat {
    /// JS `${n}`: 80 not 80.0.
    static func number(_ n: Double) -> String {
        n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
    }
}

/// One phase on the journey rail.
private struct OnboardingTimelineRow: View {
    let phase: PresentationDeck.Phase
    let now: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .top) {
                if now {
                    Circle().fill(Color.white).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1).frame(width: 28, height: 28))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1).frame(width: 40, height: 40))
                        .padding(.top, 1)
                } else {
                    Circle().fill(Color.intent.background).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.intent.mutedForeground.opacity(0.6), lineWidth: 2))
                        .padding(.top, 4)
                }
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(phase.weeks).font(.intent(10.5)).tracking(1.26).textCase(.uppercase)
                        .foregroundStyle(Color.intent.mutedForeground)
                    Spacer()
                    if let length = phase.length {
                        Text(length).font(.intent(12))
                            .foregroundStyle(now ? Color.black : Color.intent.mutedForeground)
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(Capsule().fill(now ? Color.white : Color.intent.card))
                    }
                }
                Text(phase.title).font(.intent(19)).padding(.top, 4)
                Text(phase.motive).font(.intent(13)).lineSpacing(3).foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                if now {
                    Text("You start here").font(.intent(10)).tracking(1.2).textCase(.uppercase)
                        .foregroundStyle(Color.intent.sessionsCyan).padding(.top, 8)
                }
                if phase.deloads {
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { t in
                            if t % 2 == 1 {
                                Capsule().fill(Color.intent.mutedForeground).frame(width: 8, height: 3)
                            } else {
                                Capsule().fill(Color.intent.secondary).frame(maxWidth: .infinity).frame(height: 3)
                            }
                        }
                    }
                    .padding(.top, 10)
                    Text("Deload week every 8 weeks").font(.intent(11))
                        .foregroundStyle(Color.intent.mutedForeground.opacity(0.8)).padding(.top, 6)
                }
            }
            .padding(.bottom, 24)
        }
        // The rail runs from under the dot to the next row; as a background it takes
        // the row's height instead of growing to whatever the scroll view offers.
        .background(alignment: .topLeading) {
            rail.frame(width: 30).padding(.top, 22).padding(.bottom, -6)
        }
    }

    @ViewBuilder private var rail: some View {
        if now {
            LinearGradient(colors: [.white, .white.opacity(0.15)], startPoint: .top, endPoint: .bottom).frame(width: 2)
        } else {
            Rectangle().fill(Color.clear).frame(width: 2)
                .overlay(
                    Line().stroke(Color.intent.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                )
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
        }
    }
}

/// A session with its exercises folded away (SessionRow).
private struct OnboardingSessionRow: View {
    let day: ProgramDay
    let isLast: Bool
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.label).font(.intent(21, .light)).tracking(-0.21).lineLimit(1)
                            .foregroundStyle(Color.intent.foreground)
                        Text(day.focus).font(.intent(13)).lineLimit(1).foregroundStyle(Color.intent.mutedForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(day.exercises.count) exercises").font(.intent(13)).foregroundStyle(Color.intent.mutedForeground)
                        .fixedSize()
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open ? .isSelected : [])
            if open {
                VStack(spacing: 2) {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, ex in
                        HStack(spacing: 12) {
                            Text(ex.name).lineLimit(1).foregroundStyle(Color.intent.foreground.opacity(0.85))
                            Spacer()
                            Text("\(ex.sets) × \(ex.reps)").foregroundStyle(Color.intent.mutedForeground).fixedSize()
                        }
                        .font(.intent(13.5))
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { if !isLast { IntentDivider() } }
    }
}

/// "What would you change?" (SatisfactionGate's ProgramFeedbackSheet).
struct OnboardingFeedbackSheet: View {
    typealias Category = Components.Schemas.ProgramFeedback.CategoriesPayloadPayload

    static let labels: [(Category, String)] = [
        (.trainingDays, "Training days"), (.exercises, "Exercises"), (.sets, "Sets"), (.split, "Split"),
        (.order, "Exercise order"), (.sessionLength, "Session length"), (.equipment, "Equipment"),
        (.priorityMuscles, "Priority muscles"), (.overallVolume, "Overall volume"),
    ]

    let currentTrainingDays: Int
    let showRegenerateNudge: Bool
    var isSubmitting = false
    let onSubmit: (OnboardingFeedback) -> Void

    @State private var categories: [Category] = []
    @State private var note = ""
    @State private var trainingDays: Int?

    var body: some View {
        let changingDays = categories.contains(.trainingDays)
        let days = trainingDays ?? currentTrainingDays
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What would you change?").font(.intent(22)).tracking(-0.22)
                Text("Pick anything that applies, or just leave a note. We'll rebuild it.")
                    .intentText(.lede).foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                OnboardingWrap {
                    ForEach(Self.labels.indices, id: \.self) { i in
                        let (category, label) = Self.labels[i]
                        OnboardingChip(title: label, selected: categories.contains(category), onCard: true) {
                            if categories.contains(category) { categories.removeAll { $0 == category } } else { categories.append(category) }
                        }
                    }
                }
                .padding(.top, 20)
                if changingDays {
                    Text("Days per week").font(.intent(13.5)).foregroundStyle(Color.intent.mutedForeground)
                        .padding(.top, 16).padding(.bottom, 8)
                    HStack(spacing: 8) {
                        ForEach(Array(OnboardingOptions.trainingDayRange), id: \.self) { n in
                            OnboardingChip(title: "\(n)", selected: days == n, onCard: true) { trainingDays = n }
                        }
                    }
                }
                TextField("", text: $note, prompt: Text("Anything specific? (optional)")
                    .foregroundStyle(Color.intent.mutedForeground.opacity(0.6)), axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .font(.intent(16))
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous).fill(Color.intent.secondary))
                    .padding(.top, 16)
                if showRegenerateNudge {
                    Text("Programs improve as you train - consider starting and adjusting from real sessions instead of regenerating again.")
                        .font(.intent(12.5)).lineSpacing(3).foregroundStyle(Color.intent.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
                Button(isSubmitting ? "Rebuilding…" : "Rebuild my program") {
                    onSubmit(OnboardingFeedback(categories: categories, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                                trainingDays: changingDays ? days : nil))
                }
                .buttonStyle(.intentPrimary)
                .disabled(isSubmitting)
                .padding(.top, 20)
            }
            .foregroundStyle(Color.intent.foreground)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.height(changingDays ? 560 : 480), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.intent.card)
        .presentationCornerRadius(30)
        .interactiveDismissDisabled(isSubmitting)
    }
}

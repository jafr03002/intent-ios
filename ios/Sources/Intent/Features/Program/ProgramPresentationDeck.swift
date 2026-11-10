import IntentCore
import IntentDesign
import SwiftUI

/// "Building your program" (components/onboarding/GeneratingScreen.tsx): a turning
/// dumbbell disc and status lines that step forward every 1.8s and stop at the last.
struct ProgramGeneratingView: View {
    private static let messages = [
        "Laying out the schedule…", "Setting up workouts…", "Structuring your split…",
        "Balancing muscle groups…", "Dialing in sets and reps…", "Almost there…",
    ]

    @State private var index = 0
    @State private var spin = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "dumbbell")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.intent.foreground)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.intent.secondary))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 2.4).repeatForever(autoreverses: false), value: spin)
                .padding(.bottom, 32)
            Text("Building your program")
                .font(.intent(28, .light))
                .tracking(-0.56)
                .foregroundStyle(Color.intent.foreground)
                .padding(.bottom, 12)
            Text(Self.messages[index])
                .font(.intent(14, .regular))
                .foregroundStyle(Color.intent.mutedForeground)
                .id(index)
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.intent.background.ignoresSafeArea())
        .onAppear { spin = true }
        .task {
            while index < Self.messages.count - 1 {
                try? await Task.sleep(for: .milliseconds(1800))
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.25)) { index += 1 }
            }
        }
    }
}

/// The post-generation deck (components/onboarding/PresentationDeck.tsx), shown on
/// the AI program page after a (re)generation: a short "coach's letter" in six pages,
/// ending on "Happy with it?" with a Tweak-something feedback sheet.
///
/// NOTE: the Onboarding feature owns the onboarding copy of this deck; this is the
/// Program tab's own port until the two are merged. Simplified: no storm wash
/// (LetterWash) and plain pager dots.
struct ProgramPresentationDeck: View {
    let program: Program
    let goal: String
    var weightUnit: String?
    var name: String?
    var priorityMuscles: [String] = []
    let onSatisfied: () -> Void
    let onSubmitFeedback: (ProgramFeedbackDraft) -> Void
    var isSubmitting = false
    var showRegenerateNudge = false
    var error = false
    var initialPage = 0
    var initiallyTweaking = false

    @State private var page = 0
    @State private var tweaking = false
    @State private var didInit = false

    private var pages: [String] { ProgramPresentation.pages }
    private var current: String { pages[page] }
    private var isLast: Bool { page == pages.count - 1 }
    private var days: [ProgramDay] { program.days }
    private var unit: String { weightUnit ?? "kg" }
    private var focus: [String] { ProgramPresentation.focusMuscles(priorityMuscles) }
    private var focusText: String { ProgramPresentation.joinWithAnd(focus.map(ProgramPresentation.muscleKey)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer()
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.white : Color.intent.accent)
                        .frame(width: i == page ? 18 : 6, height: 6)
                        .onTapGesture { page = i }
                }
            }
            .padding(.horizontal, IntentSpacing.gutter)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) { pageContent }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, IntentSpacing.gutter)
                    .padding(.top, 28)
                    .padding(.bottom, 32)
                    .id(current)
                    .transition(.opacity.combined(with: .offset(x: 20)))
            }
            .scrollIndicators(.hidden)

            dock
        }
        .background(Color.intent.background.ignoresSafeArea())
        .animation(.easeOut(duration: 0.22), value: page)
        .onAppear {
            guard !didInit else { return }
            didInit = true
            page = min(max(0, initialPage), pages.count - 1)
            tweaking = initiallyTweaking
        }
        .onChange(of: program.generatedAt) { _, _ in page = 0; tweaking = false }
        .sheet(isPresented: $tweaking) {
            ProgramFeedbackSheet(
                currentTrainingDays: days.count,
                isSubmitting: isSubmitting,
                showRegenerateNudge: showRegenerateNudge,
                onSubmit: { feedback in
                    tweaking = false
                    onSubmitFeedback(feedback)
                }
            )
            .presentationDetents([.large])
            .presentationBackground(Color.intent.card)
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    // MARK: Pages

    @ViewBuilder private var pageContent: some View {
        switch current {
        case "letter": letter
        case "program": programPage
        case "journey": journey
        case "volume": volume
        case "sessions": sessions
        default: happy
        }
    }

    private var sun: some View {
        IntentSunMark(size: 44)
    }

    private func say(_ text: Text, size: CGFloat) -> some View {
        text.font(.intent(size, .light))
            .foregroundStyle(Color.intent.mutedForeground)
            .lineSpacing(size * 0.18)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func b(_ s: String) -> Text { Text(s).foregroundColor(Color.intent.foreground) }
    private func g(_ s: String) -> Text { Text(s) }

    private func pageHead(_ title: String, _ sentence: Text) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .intentText(.eyebrow)
                .foregroundStyle(Color.intent.mutedForeground)
            say(sentence, size: 24)
        }
    }

    private var letter: some View {
        let split = ProgramPresentation.splitPhrase(program.splitType)
        let longTerm = ProgramPresentation.longTermWord(goal: goal)
        let goalWeight = program.longTermGoalWeight
        let dayWords = ProgramPresentation.capitalise(ProgramPresentation.numberWord(days.count)) + " days a week"
        var line = b(dayWords) + g(", " + split + ". ")
        if let longTerm {
            var target = longTerm
            if let goalWeight { target += " toward " + fmt(goalWeight) + " " + unit }
            line = line + g("You're heading into a ") + b(target)
        } else {
            line = line + g("You'll train at ") + b("maintenance")
        }
        if focus.isEmpty {
            line = line + g(".")
        } else {
            line = line + g(", with extra focus on your ") + b(focusText) + g(".")
        }
        let greeting = name.map { $0 + ", your plan is ready." } ?? "Your plan is ready."
        return VStack(alignment: .leading, spacing: 0) {
            sun.padding(.top, 48)
            say(b(greeting), size: 32).padding(.top, 24)
            say(line, size: 22).padding(.top, 16)
        }
    }

    private var programPage: some View {
        let n = ProgramPresentation.numberWord(days.count)
        let dayCount = b(n + " days")
        var head: Text
        if focus.isEmpty {
            head = g("Built for the ") + dayCount
        } else {
            head = g("Built around your ") + b(focusText)
            head = head + g(", on the ") + dayCount
        }
        head = head + g(" you have.")
        return VStack(alignment: .leading, spacing: 0) {
            pageHead("Program", head)
            Text(program.programName)
                .font(.intent(19, .light))
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 24)
            VStack(spacing: 8) {
                if !focus.isEmpty {
                    highlightCard(eyebrow: "Your focus",
                                  title: "\(ProgramPresentation.capitalise(focusText)) come first",
                                  detail: "They get extra sets every week, so they grow ahead of the rest.")
                }
                ForEach(Array(ProgramPresentation.highlights(program).enumerated()), id: \.offset) { _, h in
                    highlightCard(eyebrow: nil, title: h.title, detail: h.detail)
                }
            }
            .padding(.top, 12)
        }
    }

    private func highlightCard(eyebrow: String?, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.intent(10, .regular)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Color.intent.sessionsCyan)
                    .padding(.bottom, 2)
            }
            Text(title).intentText(.rowTitle).foregroundStyle(Color.intent.foreground)
            Text(detail)
                .font(.intent(12.5, .regular))
                .lineSpacing(4)
                .foregroundStyle(Color.intent.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .intentSurface()
    }

    private var journey: some View {
        let phases = ProgramPresentation.timeline(goal: goal)
        let currentIndex = ProgramPresentation.currentPhaseIndex(
            phases, shortTermPhase: program.shortTermPhase?.rawValue, goal: goal)
        let goalWeight = program.longTermGoalWeight
        let rest = journeyRest(goalWeight)
        return VStack(alignment: .leading, spacing: 0) {
            pageHead("Your journey", g("Start with ") + b("a week of calibration") + g(", ") + rest)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(phases.enumerated()), id: \.offset) { i, p in
                    phaseRow(p, now: i == currentIndex)
                }
                if let goalWeight, let week = ProgramPresentation.goalWeek(goal: goal) {
                    HStack(spacing: 14) {
                        Image(systemName: "flag")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(fmt(goalWeight)) \(unit)").font(.intent(30, .light))
                            Text("Goal · week \(week)").intentText(.eyebrow).foregroundStyle(Color.intent.mutedForeground)
                        }
                    }
                }
            }
            .padding(.top, 32)
        }
    }

    private func journeyRest(_ goalWeight: Double?) -> Text {
        let target = goalWeight.map { fmt($0) + " " + unit }
        if goal == "gain_weight" {
            if let target { return g("then a ") + b("bulk") + g(" all the way to ") + b(target) + g(".") }
            return g("then a ") + b("bulk") + g(" to build size.")
        }
        if goal == "lose_weight" {
            if let target { return g("then ") + b("step by step") + g(" down to ") + b(target) + g(".") }
            return g("then ") + b("step by step") + g(" down.")
        }
        return g("then ") + b("steady training") + g(" at maintenance.")
    }

    private func phaseRow(_ p: PresentationPhase, now: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(now ? Color.white.opacity(0.6) : Color.intent.accent)
                    .frame(width: 2)
                    .padding(.top, 22)
                Circle()
                    .fill(now ? Color.white : Color.intent.background)
                    .overlay(Circle().strokeBorder(now ? Color.clear : Color.intent.mutedForeground.opacity(0.6), lineWidth: 2))
                    .frame(width: now ? 18 : 12, height: now ? 18 : 12)
                    .padding(.top, now ? 1 : 4)
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(p.weeks).intentText(.eyebrow).foregroundStyle(Color.intent.mutedForeground)
                    Spacer()
                    if let length = p.length {
                        Text(length)
                            .font(.intent(12, .regular))
                            .foregroundStyle(now ? Color.black : Color.intent.mutedForeground)
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(Capsule().fill(now ? Color.white : Color.intent.card))
                    }
                }
                Text(p.title).font(.intent(19, .regular)).foregroundStyle(Color.intent.foreground).padding(.top, 4)
                Text(p.motive)
                    .font(.intent(13, .regular))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                if now {
                    Text("You start here")
                        .font(.intent(10, .regular)).tracking(1.2).textCase(.uppercase)
                        .foregroundStyle(Color.intent.sessionsCyan)
                        .padding(.top, 8)
                }
                if p.deloads {
                    Text("Deload week every 8 weeks")
                        .font(.intent(11, .regular))
                        .foregroundStyle(Color.intent.mutedForeground.opacity(0.8))
                        .padding(.top, 10)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var volume: some View {
        let rows = ProgramPresentation.weeklyVolume(days)
        let total = rows.reduce(0) { $0 + $1.sets }
        let maxSets = max(1, rows.map(\.sets).max() ?? 1)
        let focusKeys = Set(focus.map(ProgramPresentation.muscleKey))
        let week = ProgramPresentation.weekFromSchedule(program)
        var head = b(String(total) + " hard sets")
        if focus.isEmpty {
            head = head + g(" a week, spread across every muscle.")
        } else {
            head = head + g(" a week, with extra for your ") + b(focusText) + g(".")
        }
        return VStack(alignment: .leading, spacing: 0) {
            pageHead("Volume", head)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    let prioritised = focusKeys.contains(row.muscle)
                    HStack(spacing: 12) {
                        Text(ProgramPresentation.capitalise(row.muscle) + (prioritised ? " ·" : ""))
                            .font(.intent(13.5, .regular))
                            .foregroundStyle(Color.intent.foreground.opacity(prioritised ? 1 : 0.8))
                            .lineLimit(1)
                            .frame(width: 104, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.intent.card)
                                Capsule().fill(prioritised ? Color.white : Color.intent.mutedForeground)
                                    .frame(width: geo.size.width * CGFloat(row.sets) / CGFloat(maxSets))
                            }
                        }
                        .frame(height: 3)
                        Text("\(row.sets)")
                            .font(.intent(13, .regular))
                            .foregroundStyle(Color.intent.mutedForeground)
                            .frame(width: 24, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { IntentDivider() } }
                }
            }
            .padding(.top, 20)

            Text("Your week").intentText(.eyebrow).foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 28).padding(.bottom, 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(ProgramScheduleReader.weekdayLabels, id: \.self) { wd in
                    Text(wd).font(.intent(10, .medium)).foregroundStyle(Color.intent.mutedForeground)
                }
                ForEach(Array(week.enumerated()), id: \.offset) { _, d in
                    if let d {
                        Text(d.label)
                            .font(.intent(9.5, .medium))
                            .foregroundStyle(Color.intent.foreground)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                            .padding(.horizontal, 4).padding(.vertical, 6)
                            .background(Color.intent.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.intent.border, lineWidth: 1)
                            .frame(minHeight: 68)
                    }
                }
            }
            Text(ProgramPresentation.isRealSchedule(program)
                 ? "\(days.count) training days a week, on the days you kept free."
                 : "\(days.count) training days a week, with rest spread between them.")
                .font(.intent(11, .regular))
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 8)
        }
    }

    private var sessions: some View {
        let n = ProgramPresentation.capitalise(ProgramPresentation.numberWord(days.count))
        let duration = ProgramPresentation.durationText(days)
        var head = b(n + " sessions")
        if let duration {
            head = head + g(", about ") + b(duration) + g(" each.")
        } else {
            head = head + g(".")
        }
        return VStack(alignment: .leading, spacing: 0) {
            pageHead("Sessions", head)
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    ProgramDeckSessionRow(day: d)
                        .overlay(alignment: .top) { if i > 0 { IntentDivider() } }
                }
            }
            .padding(.top, 20)
        }
    }

    private var happy: some View {
        VStack(alignment: .leading, spacing: 0) {
            sun.padding(.top, 48)
            say(b("Happy with it?"), size: 32).padding(.top, 24)
            say(g("You can change anything before you start. Once you're training, I'll adjust it from your real sessions."), size: 20)
                .padding(.top, 16)
            if error {
                Text("Something went wrong rebuilding your program. Please try again.")
                    .font(.intent(13, .regular))
                    .foregroundStyle(Color.intent.destructive)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .intentSurface(radius: IntentRadius.notice)
                    .padding(.top, 24)
            }
        }
    }

    // MARK: Dock

    private var dock: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if page > 0 {
                    Button { page -= 1 } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.intentOutline)
                        .frame(width: 72)
                        .accessibilityLabel("Back")
                }
                Button(current == "letter" ? "Show me" : isLast ? "Yes, let's go" : "Next") {
                    if isLast { onSatisfied() } else { page = min(pages.count - 1, page + 1) }
                }
                .buttonStyle(.intentPrimary)
                .disabled(isLast && isSubmitting)
            }
            if isLast {
                HStack(spacing: 4) {
                    Text("Not quite?").foregroundStyle(Color.intent.mutedForeground)
                    Button("Tweak something") { tweaking = true }
                        .foregroundStyle(Color.intent.foreground)
                        .underline()
                }
                .font(.intent(13, .regular))
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, IntentSpacing.gutter)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}

/// One deck session row: day label over focus, the count, and it expands to its exercises.
private struct ProgramDeckSessionRow: View {
    let day: ProgramDay
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.label).font(.intent(21, .light)).foregroundStyle(Color.intent.foreground).lineLimit(1)
                        Text(day.focus).font(.intent(13, .regular)).foregroundStyle(Color.intent.mutedForeground).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(day.exercises.count) exercises")
                        .font(.intent(13, .regular))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .fixedSize()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(spacing: 2) {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, ex in
                        HStack {
                            Text(ex.name).foregroundStyle(Color.intent.foreground.opacity(0.85)).lineLimit(1)
                            Spacer()
                            Text("\(ex.sets) × \(ex.reps)").foregroundStyle(Color.intent.mutedForeground).fixedSize()
                        }
                        .font(.intent(13.5, .regular))
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(.vertical, 16)
    }
}

/// "What would you change?" (SatisfactionGate's ProgramFeedbackSheet).
struct ProgramFeedbackSheet: View {
    let currentTrainingDays: Int
    var isSubmitting = false
    var showRegenerateNudge = false
    let onSubmit: (ProgramFeedbackDraft) -> Void

    @State private var categories: [ProgramFeedbackCategory] = []
    @State private var note = ""
    @State private var trainingDays = 0
    @State private var didInit = false

    private var changingDays: Bool { categories.contains(.trainingDays) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color.intent.accent).frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity).padding(.bottom, 20)
                Text("What would you change?")
                    .font(.intent(22, .regular))
                    .foregroundStyle(Color.intent.foreground)
                Text("Pick anything that applies, or just leave a note. We'll rebuild it.")
                    .font(.intent(13.5, .regular))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .padding(.top, 6)

                ProgramFlowLayout(spacing: 8) {
                    ForEach(ProgramFeedbackCategory.allCases, id: \.self) { c in
                        ProgramSheetChip(title: c.label, isSelected: categories.contains(c)) {
                            if let i = categories.firstIndex(of: c) { categories.remove(at: i) } else { categories.append(c) }
                        }
                    }
                }
                .padding(.top, 20)

                if changingDays {
                    Text("Days per week")
                        .font(.intent(13.5, .regular))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .padding(.top, 16).padding(.bottom, 8)
                    HStack(spacing: 8) {
                        ForEach(ProgramFeedbackCategory.trainingDayOptions, id: \.self) { n in
                            ProgramSheetChip(title: "\(n)", isSelected: trainingDays == n) { trainingDays = n }
                        }
                    }
                }

                TextField("", text: $note, prompt: Text("Anything specific? (optional)")
                    .foregroundStyle(Color.intent.mutedForeground.opacity(0.6)), axis: .vertical)
                    .lineLimit(3...6)
                    .font(.intent(15, .regular))
                    .foregroundStyle(Color.intent.foreground)
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .background(Color.intent.secondary, in: RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous))
                    .padding(.top, 16)

                if showRegenerateNudge {
                    Text("Programs improve as you train - consider starting and adjusting from real sessions instead of regenerating again.")
                        .font(.intent(12.5, .regular))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .padding(.top, 12)
                }

                Button(isSubmitting ? "Rebuilding…" : "Rebuild my program") {
                    onSubmit(ProgramFeedbackDraft(
                        categories: categories,
                        note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                        trainingDays: changingDays ? trainingDays : nil
                    ))
                }
                .buttonStyle(.intentPrimary)
                .disabled(isSubmitting)
                .padding(.top, 20)
            }
            .padding(.horizontal, IntentSpacing.gutter)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if !didInit { didInit = true; trainingDays = currentTrainingDays }
        }
    }
}

/// A chip on the sheet: the sheet is already `bg-card`, so unselected steps up to secondary.
private struct ProgramSheetChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.intent(14, isSelected ? .medium : .regular))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? Color.black : Color.intent.mutedForeground)
                .background(Capsule().fill(isSelected ? Color.white : Color.intent.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A wrapping row of chips (`flex flex-wrap gap-2`).
struct ProgramFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

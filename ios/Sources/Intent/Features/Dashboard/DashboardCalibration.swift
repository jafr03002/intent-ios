import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// components/calibration/CalibrationWalkthrough.tsx: shown once, in place of the
/// dashboard, the first time a client is inside an active calibration window. Two
/// "coach's letter" pages, then "Show me around" marks it seen.
struct DashboardCalibrationWalkthrough: View {
    let calibrationStart: Date
    let onFinish: @MainActor () async -> Bool

    @State private var step: Int
    @State private var isSaving = false

    init(calibrationStart: Date, initialStep: Int = 0, onFinish: @escaping @MainActor () async -> Bool) {
        self.calibrationStart = calibrationStart
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    private static let focusItems: [(icon: String, title: String, detail: String)] = [
        ("dumbbell", "Try the program", "Run through your sessions and get a feel for the plan."),
        ("mappin.and.ellipse", "Learn your gym", "Find where every exercise lives and get comfortable with the equipment."),
        ("scope", "Standardise your form", "Settle into consistent technique you can build on."),
    ]
    /// A review can be asked for from the day after the first week (the day-8 rule).
    private static let reviewFromDay = 8
    private static let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var isLast: Bool { step == 1 }

    var body: some View {
        ZStack(alignment: .top) {
            Color.intent.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Spacer()
                        pageDots
                    }
                    .padding(.top, 16)
                    Group {
                        if step == 0 { intro } else { review }
                    }
                    .padding(.top, 28)
                    .id(step)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 20)),
                                            removal: .opacity.combined(with: .offset(x: -20))))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 140)
                .background(alignment: .top) {
                    DashboardWash().frame(height: 560 + 120).offset(y: -120)
                }
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
        .foregroundStyle(Color.intent.foreground)
    }

    // MARK: Pages

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHead("Calibration", say("Your first week is about ", b: "learning the program", ", not lifting heavy."))
            VStack(spacing: 0) {
                ForEach(Array(Self.focusItems.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .light))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.intent.card))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.intent(16)).foregroundStyle(Color.intent.foreground)
                            Text(item.detail).font(.intent(13)).lineSpacing(4).foregroundStyle(Color.intent.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 16)
                    .overlay(alignment: .bottom) {
                        if i < Self.focusItems.count - 1 { IntentDivider() }
                    }
                }
            }
            .padding(.top, 28)
            Text("Everything you notice feeds back to your coach, who fine-tunes your program from it.")
                .font(.intent(13)).lineSpacing(4).foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 20)
        }
    }

    private var review: some View {
        let todayNumber = DashboardLogic.calibrationDayNumber(start: calibrationStart)
        let reviewDate = Calibration.addDays(calibrationStart, Self.reviewFromDay - 1)
        return VStack(alignment: .leading, spacing: 0) {
            pageHead("Your review", say("After ", b: "your first week", ", ask for your review ", b2: "whenever you're ready", "."))
            HStack(alignment: .top, spacing: 6) {
                ForEach(0..<(Self.reviewFromDay - 1), id: \.self) { i in
                    let dayNumber = i + 1
                    let date = Calibration.addDays(calibrationStart, i)
                    let isToday = dayNumber == todayNumber
                    let past = dayNumber < todayNumber
                    VStack(spacing: 6) {
                        Text(weekday(date)).font(.intent(10)).tracking(0.6).textCase(.uppercase)
                            .foregroundStyle(Color.intent.mutedForeground)
                            .lineLimit(1).fixedSize()
                        Circle()
                            .fill(isToday ? Color.white : Color.intent.card)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 40)
                            .overlay {
                                Text("\(dayOfMonth(date))")
                                    .font(.intent(13, isToday ? .medium : .regular))
                                    .foregroundStyle(isToday ? Color.black : past ? Color.intent.mutedForeground : Color.intent.foreground)
                                    .lineLimit(1).fixedSize()
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
                VStack(spacing: 6) {
                    Text("Review").font(.intent(10)).tracking(0.6).textCase(.uppercase)
                        .foregroundStyle(Color.intent.sessionsCyan)
                        .lineLimit(1).fixedSize()
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 1.5)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 40)
                        .overlay {
                            Image(systemName: "flag").font(.system(size: 12, weight: .semibold))
                        }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 32)

            VStack(spacing: 0) {
                letterRow("Ask for your review", "from \(weekday(reviewDate)) \(dayOfMonth(reviewDate))", divider: true)
                // NOTE (ported): nothing on the backend runs this on its own yet (no cron).
                letterRow("If you don't ask", "it happens on its own", divider: false)
            }
            .padding(.top, 24)
            Text("Your coach looks back at the week, then sets your real targets for what comes next.")
                .font(.intent(13)).lineSpacing(4).foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 16)
        }
    }

    // MARK: Letter kit (components/onboarding/letter.tsx)

    /// `Say`: facts white, the words between grey, light 20pt.
    private func say(_ a: String, b: String, _ c: String, b2: String? = nil, _ d: String = "") -> Text {
        var t = Text(a).foregroundColor(Color.intent.mutedForeground) + Text(b).foregroundColor(Color.intent.foreground)
            + Text(c).foregroundColor(Color.intent.mutedForeground)
        if let b2 { t = t + Text(b2).foregroundColor(Color.intent.foreground) + Text(d).foregroundColor(Color.intent.mutedForeground) }
        return t
    }

    private func pageHead(_ title: String, _ sentence: Text) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).intentText(.screenTitle)
            sentence.font(.intent(20, .light)).tracking(-0.4).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func letterRow(_ title: String, _ value: String, divider: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.intent(15)).foregroundStyle(Color.intent.foreground)
            Spacer(minLength: 0)
            Text(value).font(.intent(14)).foregroundStyle(Color.intent.mutedForeground).lineLimit(1)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { if divider { IntentDivider() } }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(i == step ? Color.white : Color.intent.secondary)
                    .frame(width: i == step ? 24 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(step + 1) of 2")
    }

    /// `LetterDock`: one white pill in thumb reach, a round Back beside it.
    private var dock: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.22)) { step = max(0, step - 1) }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.intent.foreground)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.intent.card))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            Button(isLast ? "Show me around" : "Next") {
                if isLast {
                    Task {
                        isSaving = true
                        _ = await onFinish()
                        isSaving = false
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.22)) { step = min(1, step + 1) }
                }
            }
            .buttonStyle(.intentPrimary)
            .disabled(isSaving)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 16 + IntentMetrics.tabBarHeight)
        .background(
            LinearGradient(colors: [.clear, Color.black.opacity(0.9), .black], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false))
    }

    // MARK: Dates (local)

    private func weekday(_ d: Date) -> String {
        Self.weekdayShort[Calendar.current.component(.weekday, from: d) - 1]
    }

    private func dayOfMonth(_ d: Date) -> Int { Calendar.current.component(.day, from: d) }
}

/// The preCalibrationPhase lock: an AI program committed to a future start date.
/// Takes precedence over the walkthrough.
struct DashboardPreCalibrationLock: View {
    let name: String
    let startDate: String
    let onStartToday: @MainActor () async -> Bool

    @State private var isSaving = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: IntentSpacing.section) {
            IntentBrandMark()
            VStack(alignment: .leading, spacing: 4) {
                DashboardEyebrow(text: DashboardLogic.greeting())
                DashboardTitle(text: name)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("You chose to start on \(DashboardFormat.date(startDate, "EEE, MMM d")) but you can start today.")
                    .intentText(.body)
                    .foregroundStyle(Color.intent.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if failed {
                    Text("Couldn't update your start date. Please try again.")
                        .font(.intent(12, .medium)).foregroundStyle(Color.intent.destructive)
                }
                Button {
                    Task {
                        isSaving = true
                        failed = !(await onStartToday())
                        isSaving = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(.black).controlSize(.small) }
                        Text("Start today")
                    }
                }
                .buttonStyle(.intentPrimary)
                .fixedSize()
                .disabled(isSaving)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .intentSurface(radius: IntentRadius.groupedList)
        }
    }
}

import IntentCore
import IntentDesign
import SwiftUI

/// The bridge between a Start press and the logger during calibration (web:
/// pages/calibration-briefing.tsx). The session clock doesn't run while the client
/// reads, and backing out leaves nothing behind; "Start session" on the last card
/// is what starts it. Full screen, over the tab bar.
struct CalibrationBriefingScreen: View {
    let dayNumber: Int
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0

    private var total: Int { CalibrationBriefing.stepCount }
    private var isLast: Bool { step == total - 1 }
    private var program: Program? { launcher.program }
    private var day: ProgramDay? { program?.days.first { $0.dayNumber == dayNumber } }
    /// Once read through to the end, later sessions may skip straight in.
    private var canSkip: Bool { launcher.profile?.calibrationBriefingSeenAt != nil }

    var body: some View {
        ZStack(alignment: .top) {
            Color.intent.background.ignoresSafeArea()
            // A quiet grey-to-teal light on the first and last cards (the web's LetterWash bookends).
            LinearGradient(colors: [Color.intent.sessionsCyan.opacity(step == 0 || isLast ? 0.10 : 0.04), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.3), value: step)

            VStack(spacing: 0) {
                topBar
                card
                Spacer(minLength: 0)
                dock
            }
        }
        .foregroundStyle(Color.intent.foreground)
        .onAppear {
            // Not (or no longer) a calibration session: nothing to say, start normally.
            if let program, CalibrationBriefing.shouldSkipBriefing(program, today: Date()) { start() }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .light))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.intent.card))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule().fill(i == step ? Color.white : Color.intent.mutedForeground.opacity(0.4))
                        .frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: step)
            .accessibilityLabel("\(step + 1) of \(total)")
        }
        .padding(.horizontal, IntentSpacing.gutter)
        .padding(.top, 8)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(CalibrationBriefing.eyebrow(dayLabel: day?.label))
                .intentText(.eyebrow)
                .foregroundStyle(Color.intent.sessionsCyan)
            Group {
                if isLast {
                    VStack(spacing: 0) {
                        IntentSunMark(size: 52)
                        Text("Good luck!").intentText(.screenTitle).padding(.top, 24)
                        Text("Tick each set off as you go.").font(.intent(15))
                            .foregroundStyle(Color.intent.mutedForeground).padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 96)
                } else {
                    let point = CalibrationBriefing.points[step]
                    VStack(alignment: .leading, spacing: 0) {
                        if step == 0 {
                            Text(CalibrationBriefing.intro).font(.intent(15)).lineSpacing(5)
                                .foregroundStyle(Color.intent.mutedForeground).padding(.top, 12)
                        }
                        Text(point.title).font(.intent(30, .light)).tracking(-0.75).lineSpacing(1)
                            .padding(.top, 56)
                        Text(point.body).font(.intent(17, .light)).lineSpacing(5)
                            .foregroundStyle(Color.intent.mutedForeground).padding(.top, 16)
                        Text("Tap to continue").intentText(.caps)
                            .foregroundStyle(Color.intent.mutedForeground.opacity(0.7)).padding(.top, 64)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 20)),
                                    removal: .opacity.combined(with: .offset(x: -20))))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, IntentSpacing.gutter)
        .padding(.top, 32)
        .contentShape(Rectangle())
        // Tapping anywhere on the card moves on, like turning a page.
        .onTapGesture { if !isLast { next() } }
    }

    private var dock: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if step > 0 {
                    Button("Back") { withAnimation(.easeOut(duration: 0.22)) { step = max(0, step - 1) } }
                        .buttonStyle(.intentOutline)
                }
                Button(isLast ? "Start session" : "Next") { next() }
                    .buttonStyle(.intentPrimary)
            }
            if canSkip && !isLast {
                Button { start() } label: {
                    Text("Skip to the session").font(.intent(13)).foregroundStyle(Color.intent.mutedForeground)
                        .frame(maxWidth: .infinity).frame(height: 36)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, IntentSpacing.gutter)
        .padding(.bottom, 16)
    }

    private func next() {
        if isLast {
            launcher.markBriefingSeen()
            start()
        } else {
            withAnimation(.easeOut(duration: 0.22)) { step = min(total - 1, step + 1) }
        }
    }

    private func start() {
        launcher.briefingDay = nil
        launcher.startSessionNow(dayNumber: dayNumber)
    }
}

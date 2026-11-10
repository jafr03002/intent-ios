import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// The workout logger (web: pages/log.tsx). It only ever logs the one session in
/// progress; sessions start from the Start picker or the program page. Opened by
/// `WorkoutLauncher` (see MainTabView), or standalone.
struct LogScreen: View {
    var request: LogRequest = LogRequest()
    var debugShowCalibrationFinish = false

    @Environment(AppServices.self) private var services
    @Environment(WorkoutLauncher.self) private var launcher: WorkoutLauncher?
    @State private var model: LogModel?
    @State private var localToast: LogToast?

    init() {}

    init(request: LogRequest, debugShowCalibrationFinish: Bool = false) {
        self.request = request
        self.debugShowCalibrationFinish = debugShowCalibrationFinish
    }

    var body: some View {
        ZStack {
            Color.intent.background.ignoresSafeArea()
            if let model {
                LogContent(model: model)
            } else {
                LogLoadingView()
            }
        }
        .overlay(alignment: .top) { if launcher == nil { LogToastStack(toast: localToast) } }
        .task {
            guard model == nil else { return }
            let client = launcher?.client ?? services.api.api
            let store = launcher?.store ?? WorkoutSessionStore(store: LogUserDefaultsStore())
            let m = LogModel(client: client, store: store, request: request, launcher: launcher,
                             showCalibrationFinish: debugShowCalibrationFinish,
                             toast: { localToast = $0 })
            model = m
            await m.load()
        }
    }
}

struct LogLoadingView: View {
    var body: some View {
        Text("Loading workout...")
            .font(.intent(14))
            .foregroundStyle(Color.intent.mutedForeground)
            .frame(maxWidth: .infinity, minHeight: 256)
    }
}

private struct LogContent: View {
    @Bindable var model: LogModel
    @Environment(WorkoutLauncher.self) private var launcher: WorkoutLauncher?
    @FocusState private var focus: LogFieldID?
    @State private var focusEnteredCompleted = false
    @State private var howTo: LogHowToItem?

    var body: some View {
        Group {
            if model.program != nil && model.isLocked {
                LogLoadingView()
                    .alert("You can't log workouts yet", isPresented: .constant(true)) {
                        Button("Cancel", role: .cancel) { leave(to: .home) }
                        Button("I'm ready - start today") { Task { await model.startToday() } }
                    } message: {
                        Text("You can't log workouts before committing to training. Click here if you're ready to start today.")
                    }
            } else if model.programLoaded && model.program == nil && model.profile != nil {
                page {
                    LogEmptyState(
                        title: "No program to log yet",
                        message: model.isIndependent
                            ? "You haven't built a program yet. Create one to start logging your workouts."
                            : "You don't have a program yet. Generate one with your AI coach to start logging your workouts.",
                        cta: model.isIndependent ? "Create your program" : "Generate my program",
                        action: { leave(to: .program) })
                }
            } else if model.hasSession == false {
                page {
                    LogEmptyState(
                        title: model.controller.startFailed ? "Couldn't start your workout" : "No logging ongoing",
                        message: model.controller.startFailed
                            ? "This device won't let the app store your session, so there's nowhere to log to. Free up some storage and try again."
                            : "Head to your program page and hit Start workout on the day you're training - your session opens here.",
                        cta: "Go to my program",
                        action: { leave(to: .program) })
                }
            } else if model.program == nil || model.activeDay == nil {
                LogLoadingView()
            } else {
                logger
            }
        }
        .task(id: model.hasRunningTimer) {
            // The session clock (1 s) and, only while a countdown runs, 250 ms.
            let step: Duration = model.hasRunningTimer ? .milliseconds(250) : .seconds(1)
            while !Task.isCancelled {
                model.tick()
                try? await Task.sleep(for: step)
            }
        }
    }

    private func leave(to tab: IntentTabBar.Tab) {
        if let launcher {
            launcher.closeLog()
            launcher.selectTab?(tab)
        }
    }

    private func page<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView {
            content().padding(IntentSpacing.gutter)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Logger

    private var logger: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, IntentSpacing.section)
                    VStack(spacing: 14) {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { exIdx, ex in
                            card(ex, exIdx)
                        }
                    }
                    finishButton
                        .padding(.top, 32)
                }
                .padding(IntentSpacing.gutter)
                .foregroundStyle(Color.intent.foreground)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Rows scrolled up stop at the status bar instead of running under the clock.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0)
                    .background(Color.intent.background.ignoresSafeArea(edges: .top))
            }
            .onChange(of: model.scrollTick) { _, _ in
                guard let target = model.scrollTarget else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo("set-\(target.exIdx)-\(target.setIdx)", anchor: .center)
                }
            }
        }
        .overlay(alignment: .top) { prToasts }
        .onChange(of: focus) { old, new in focusChanged(from: old, to: new) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
                    .font(.intent(15, .medium))
            }
        }
        .sheet(isPresented: $model.showIncompleteConfirm) {
            LogConfirmSheet(
                title: "Not every set is logged",
                message: "Looks like some sets are still missing a weight or rep count. Finish anyway, or go back and fill them in?",
                cancelLabel: "Keep logging", confirmLabel: "Finish anyway", destructive: false,
                onCancel: { model.showIncompleteConfirm = false },
                onConfirm: {
                    model.showIncompleteConfirm = false
                    Task { await model.finishWorkout(note: nil) }
                })
                .logSheetChrome(height: 250)
        }
        .sheet(isPresented: $model.showCancelConfirm) {
            LogConfirmSheet(
                title: "Discard this workout?",
                message: "Everything you've logged in this session will be lost - it won't be saved.",
                cancelLabel: "Keep logging", confirmLabel: "Discard workout", destructive: true,
                onCancel: { model.showCancelConfirm = false },
                onConfirm: { model.cancelWorkout() })
                .logSheetChrome(height: 230)
        }
        .sheet(isPresented: $model.showCalibrationFinish) {
            CalibrationFinishSheet(saving: model.saving) { note in
                Task { await model.finishWorkout(note: note) }
            }
            .logSheetChrome(height: 520)
        }
        .sheet(item: $howTo) { item in
            LogHowToSheet(name: item.name, muscle: item.muscle, cue: item.cue)
                .logSheetChrome(height: 260)
        }
    }

    /// Only a set finished during this visit moves the page on, and only when the
    /// keyboard is dismissed (focus lands on nothing) - tapping straight into another
    /// input is the user choosing where to go.
    private func focusChanged(from old: LogFieldID?, to new: LogFieldID?) {
        if let new, new.row != old?.row {
            focusEnteredCompleted = model.logs[logAt: new.exIdx]?.sets[logAt: new.setIdx]?.completed ?? false
        }
        if new == nil, let old, model.logs[logAt: old.exIdx]?.sets[logAt: old.setIdx]?.completed == true,
           !focusEnteredCompleted {
            model.scrollToNextSet()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.activeDay?.label ?? "Workout")
                        .intentText(.screenTitle)
                        .foregroundStyle(Color.intent.foreground)
                    HStack(spacing: 8) {
                        if model.isCalibration {
                            Text("Calibration · tick each set")
                                .intentText(.badge)
                                .foregroundStyle(Color.intent.sessionsCyan)
                        }
                        if let elapsed = model.elapsedSeconds {
                            HStack(spacing: 6) {
                                Image(systemName: "clock").font(.system(size: 12, weight: .light))
                                Text(SessionDuration.formatClock(Double(elapsed))).monospacedDigit()
                            }
                            .font(.intent(13))
                            .foregroundStyle(Color.intent.mutedForeground)
                            .accessibilityLabel("Session time \(SessionDuration.formatClock(Double(elapsed)))")
                        }
                        if model.sessionPrCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "trophy").font(.system(size: 10, weight: .light))
                                Text(LogScreenRules.prBadge(model.sessionPrCount)).intentText(.badge)
                            }
                            .foregroundStyle(Color.intent.sessionsCyan)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.intent.sessionsCyan.opacity(0.1)))
                            .transition(.scale)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: model.sessionPrCount)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IntentIconButton("Cancel workout", systemImage: "xmark") { model.showCancelConfirm = true }
            }
            if model.controller.resumedElsewhere {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").font(.system(size: 15, weight: .light)).padding(.top, 1)
                    Text("Resuming your in-progress session - finish it before starting a new one.")
                        .font(.intent(12.5)).lineSpacing(3)
                }
                .foregroundStyle(Color.intent.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.intent.card, in: RoundedRectangle(cornerRadius: IntentRadius.notice, style: .continuous))
            }
        }
    }

    @ViewBuilder private func card(_ ex: DraftExercise, _ exIdx: Int) -> some View {
        if ex.kind == .checklist {
            ChecklistItemLogCard(
                ex: ex, showTargets: model.showTargets, now: model.now,
                onCompleteRound: { model.completeChecklistRound(exIdx) },
                onToggleRound: { model.toggleChecklistRound(exIdx) },
                onStart: { model.startTimer(exIdx) },
                onPause: { model.pauseTimer(exIdx) },
                onReset: { model.resetTimer(exIdx) })
        } else {
            ExerciseLogCard(
                ex: ex, exIdx: exIdx, weightUnit: model.weightUnit, showTargets: model.showTargets,
                showHelp: !model.isIndependent,
                showProgressionTargets: !model.isIndependent && model.showTargets && !model.isCalibration,
                calibration: model.isCalibration,
                prevSets: model.prevSets(for: ex), prevNote: model.prevNote(for: ex),
                focus: $focus,
                onUpdateSet: { setIdx, field, value in model.updateSet(exIdx: exIdx, setIdx: setIdx, field: field, value: value) },
                onToggleSet: { setIdx in model.toggleSetDone(exIdx: exIdx, setIdx: setIdx) },
                onUpdateNotes: { model.updateNotes(exIdx, $0) },
                onToggleNotes: { model.toggleNotes(exIdx) },
                onHelp: {
                    let cue = model.activeDay?.exercises.first { $0.name == ex.name }?.cue
                    howTo = LogHowToItem(name: ex.name, muscle: ex.muscle, cue: cue)
                })
        }
    }

    /// Finishing lives at the end of the list, in normal flow: scrolling past the
    /// last exercise is the natural end of a session.
    private var finishButton: some View {
        Button { model.handleFinishTap() } label: {
            HStack(spacing: 8) {
                if model.saving {
                    ProgressView().tint(.black)
                    Text("Saving...")
                } else {
                    if model.sessionPrCount > 0 {
                        Image(systemName: "trophy").font(.system(size: 14, weight: .regular))
                    }
                    Text(LogScreenRules.finishTitle(prCount: model.sessionPrCount))
                }
            }
            .intentText(.button)
            .frame(maxWidth: .infinity)
            .frame(height: IntentMetrics.controlHeight)
            .foregroundStyle(Color.intent.primaryForeground)
            .background(Capsule().fill(Color.intent.primary.opacity(model.saving ? 0.6 : 1)))
        }
        .buttonStyle(.plain)
        .disabled(model.saving)
    }

    /// PR toasts: pills dropping in at the top centre.
    private var prToasts: some View {
        VStack(spacing: 8) {
            ForEach(model.prFlashes) { flash in
                HStack(spacing: 12) {
                    Image(systemName: "trophy")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color.intent.sessionsCyan)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.intent.sessionsCyan.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("New personal record").font(.intent(10.5)).tracking(1.26).textCase(.uppercase)
                            .foregroundStyle(Color.intent.mutedForeground)
                        Text("\(flash.exercise) - \(LogScreenRules.formatNumber(flash.weight)) \(model.weightUnit)")
                            .font(.intent(13.5, .medium)).foregroundStyle(Color.intent.foreground).lineLimit(1)
                    }
                }
                .padding(.leading, 10).padding(.trailing, 20).padding(.vertical, 10)
                .background(Capsule().fill(Color.intent.secondary.opacity(0.95)))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.easeOut(duration: 0.2), value: model.prFlashes)
        .allowsHitTesting(false)
    }
}

import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// Opens the tab shell in a given workout state for the CI screenshots
/// (`-IntentScreen log`, `log-midsession`, `log-calibration`, ...). It seeds the
/// on-device draft the way a real session would have left it, then opens the
/// logger through the launcher, so what's captured is the real flow. Calibration
/// variants read the `calibration` fixture scenario whatever -IntentMockScenario says.
struct LogDebugHost: View {
    enum Variant {
        /// Day 1 just started (Upper A): the top of a fresh logger.
        case fresh
        /// Day 2 (Lower A) part-way: PR, unilateral L/R, a running countdown; opens
        /// scrolled to the next set.
        case midsession
        /// A calibration session (tick mode) with a few sets ticked and a note.
        case calibration
        /// The same, with the "Good job" finish sheet up.
        case calibrationFinish
        /// Nothing in progress: the idle screen.
        case empty
        /// A session running, logger closed: the live Start disc on the dashboard.
        case startLive
        /// The calibration briefing for day 2.
        case briefing
    }

    let variant: Variant
    @Environment(AppServices.self) private var services
    @State private var launcher: WorkoutLauncher?

    private var usesCalibration: Bool {
        switch variant {
        case .calibration, .calibrationFinish, .briefing: true
        default: false
        }
    }

    var body: some View {
        Group {
            if let launcher {
                MainTabView(initialTab: variant == .startLive ? .home : .program, launcher: launcher)
            } else {
                Color.intent.background.ignoresSafeArea()
            }
        }
        .task { await seed() }
    }

    private func seed() async {
        let api: IntentAPIClient = usesCalibration && services.isMock
            ? IntentAPIClient(environment: .production, transport: FixtureTransport(scenario: "calibration"))
            : services.api
        // A separate store, so seeded sessions never leak into other screens' screenshots.
        let debugDefaults = UserDefaults(suiteName: "com.jakobfreij.Intent.debug-log") ?? .standard
        let launcher = WorkoutLauncher(api: api, keyValueStore: LogUserDefaultsStore(defaults: debugDefaults))
        await launcher.attach(services)
        let store = launcher.store!
        guard let userId = launcher.userId, let program = launcher.program else {
            self.launcher = launcher
            return
        }
        store.discardActiveSession(userId: userId)
        let now = logNowMs()
        let history: [WorkoutLog]? = try? await LogAPI.history(api.api)

        func seedDay(_ dayNumber: Int, minutesAgo: Double, edit: (inout [DraftExercise], inout PrDetector) -> Void) {
            guard let day = program.days.first(where: { $0.dayNumber == dayNumber }) else { return }
            store.startSession(userId: userId, programId: program.id, dayNumber: dayNumber)
            var logs = SessionLogs.buildFreshLogs(day)
            var detector = PrDetector(history: history, personalRecords: nil)
            edit(&logs, &detector)
            store.saveDraft(key: WorkoutSession.draftKey(userId: userId, programId: program.id, dayNumber: dayNumber),
                            logs: logs, startedAt: now - minutesAgo * 60_000)
        }

        switch variant {
        case .fresh:
            seedDay(1, minutesAgo: 2) { _, _ in }
        case .midsession, .startLive:
            seedDay(2, minutesAgo: 23) { logs, pr in
                func enter(_ ex: Int, _ set: Int, _ field: SetField, _ value: Double) {
                    logs = SetEditing.updateSet(logs, exIdx: ex, setIdx: set, field: field, value: value, prDetector: &pr).logs
                }
                for (i, reps) in [7.0, 6, 5].enumerated() { enter(0, i, .weight, 102.5); enter(0, i, .reps, reps) }
                for (i, reps) in [10.0, 9, 8].enumerated() { enter(1, i, .weight, 92.5); enter(1, i, .reps, reps) }
                enter(2, 0, .weight, 21); enter(2, 0, .repsLeft, 10); enter(2, 0, .repsRight, 9)
                logs = SetEditing.updateNotes(logs, exIdx: 1, notes: "Grip went on the last set")
                if let plank = logs.firstIndex(where: { $0.kind == .checklist }) {
                    logs = SetEditing.completeChecklistRound(logs, exIdx: plank)
                    logs = SessionTimers.startTimer(logs, exIdx: plank, now: now - 13_000)
                }
            }
        case .calibration, .calibrationFinish:
            seedDay(2, minutesAgo: 18) { logs, _ in
                for s in 0..<3 { logs = SetEditing.toggleSetDone(logs, exIdx: 0, setIdx: s) }
                logs = SetEditing.toggleSetDone(logs, exIdx: 1, setIdx: 0)
                logs = SetEditing.updateNotes(logs, exIdx: 0, notes: "Squat rack was taken, used the Smith machine")
                logs = SetEditing.toggleNotes(logs, exIdx: 0)
            }
        case .empty, .briefing:
            break
        }

        switch variant {
        case .fresh: launcher.open(LogRequest(targetDayNumber: 1))
        case .midsession, .calibration: launcher.open(LogRequest(targetDayNumber: 2))
        case .calibrationFinish: launcher.route = LogRoute(request: LogRequest(targetDayNumber: 2), debugShowCalibrationFinish: true)
        case .empty: launcher.open(LogRequest())
        case .briefing: launcher.briefingDay = 2
        case .startLive: break
        }
        launcher.refreshActive()
        self.launcher = launcher
    }
}

import Foundation
import IntentDesign
import IntentAPI
import IntentCore
import Observation

/// One raised PR toast (usePrDetection's `PrFlash`).
struct LogPrFlash: Identifiable, Equatable {
    let id: Int
    var exercise: String
    var weight: Double
}

/// A set-row input's identity, for focus.
struct LogFieldID: Hashable {
    var exIdx: Int
    var setIdx: Int
    var field: SetField
    var row: SetPosition { SetPosition(exIdx: exIdx, setIdx: setIdx) }
}

/// The /log page's state: pages/log.tsx plus its hooks (useWorkoutSession via
/// `WorkoutSessionController`, usePrDetection via `PrDetector`, useSessionTimers via
/// `SessionTimers`). The rules live in IntentCore; this class only sequences them.
@MainActor
@Observable
final class LogModel {
    // MARK: Data (react-query)
    private(set) var program: Program?
    private(set) var programLoaded = false
    private(set) var profile: LogProfile?
    private(set) var history: [WorkoutLog]?
    private(set) var personalRecords: [PersonalRecord]?
    private(set) var lookup = SessionLogs.buildLastSessionLookup(nil)

    // MARK: Session
    private(set) var controller: WorkoutSessionController
    private(set) var request: LogRequest
    private var prDetector = PrDetector(history: nil, personalRecords: nil)
    private(set) var prFlashes: [LogPrFlash] = []
    @ObservationIgnored private var flashId = 0
    /// Epoch ms, re-read every tick (1 s, 250 ms while a countdown runs).
    var now: Double = logNowMs()

    // MARK: UI state
    var saving = false
    var showIncompleteConfirm = false
    var showCancelConfirm = false
    var showCalibrationFinish = false
    var startingToday = false
    /// Bumped to ask the view to scroll to `scrollTarget`.
    private(set) var scrollTick = 0
    private(set) var scrollTarget: SetPosition?
    @ObservationIgnored private var openScrollDone = false

    @ObservationIgnored let client: Client
    @ObservationIgnored let store: WorkoutSessionStore
    @ObservationIgnored weak var launcher: WorkoutLauncher?
    @ObservationIgnored private var localToast: (LogToast) -> Void = { _ in }

    init(client: Client, store: WorkoutSessionStore, request: LogRequest, launcher: WorkoutLauncher?,
         showCalibrationFinish: Bool = false, toast: @escaping (LogToast) -> Void) {
        self.client = client
        self.store = store
        self.request = request
        self.launcher = launcher
        self.controller = WorkoutSessionController(sessions: store)
        self.showCalibrationFinish = showCalibrationFinish
        self.localToast = toast
    }

    // MARK: Derived

    var logs: [DraftExercise] { controller.logs }
    var activeDay: ProgramDay? { controller.activeDay }
    var hasSession: Bool? { controller.hasSession }
    var userId: String? { profile?.userId }
    var weightUnit: String { profile?.weightUnit ?? "kg" }
    var isIndependent: Bool { profile?.isIndependent ?? false }
    var isCalibration: Bool { Calibration.isCalibrationProgram(program) }
    var isLocked: Bool { Calibration.isPreCalibrationLocked(program, today: Date()) }
    var showTargets: Bool { LogScreenRules.showTargets(isIndependent: isIndependent, historyCount: history?.count) }
    var sessionPrCount: Int { LogScreenRules.sessionPrCount(logs) }
    var elapsedSeconds: Int? { SessionTimers.elapsedSeconds(startedAt: controller.startedAt, now: now) }
    var hasRunningTimer: Bool { SessionTimers.hasRunningTimer(logs) }

    // MARK: Loading

    func load() async {
        let client = self.client
        async let profile = try? LogAPI.profile(client)
        async let program = try? LogAPI.program(client)
        async let history = try? LogAPI.history(client)
        async let prs = try? LogAPI.personalRecords(client)

        self.profile = await profile
        self.program = await program
        programLoaded = true
        sync()
        self.history = await history
        self.personalRecords = await prs
        lookup = SessionLogs.buildLastSessionLookup(self.history)
        prDetector.updateBaseline(history: self.history, personalRecords: self.personalRecords)
        openScrollIfNeeded()
    }

    /// useWorkoutSession's effect, re-run after a redirect as the hook re-runs on the
    /// new location.
    private func sync() {
        let result = controller.sync(program: program, userId: userId, request: request)
        if let redirect = result.redirect {
            request = redirect
            controller.sync(program: program, userId: userId, request: request)
        }
        launcher?.refreshActive()
    }

    /// Reopening part-way through lands on the first unlogged set, once per visit.
    private func openScrollIfNeeded() {
        guard !openScrollDone, hasSession == true, program != nil, activeDay != nil, !logs.isEmpty else { return }
        openScrollDone = true
        guard NextSet.hasAnyLoggedSet(logs), let next = NextSet.findNextUnloggedSet(logs) else { return }
        Task { @MainActor [weak self] in
            // Wait out the cards' entrance so the row is where it will stay.
            try? await Task.sleep(for: .milliseconds(350))
            self?.requestScroll(to: next)
        }
    }

    private func requestScroll(to position: SetPosition) {
        scrollTarget = position
        scrollTick += 1
    }

    /// After a set is finished: let the keyboard close, then move to the next set.
    func scrollToNextSet() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, let next = NextSet.findNextUnloggedSet(self.logs) else { return }
            self.requestScroll(to: next)
        }
    }

    // MARK: Clock

    func tick() {
        now = logNowMs()
        if let expired = SessionTimers.completeExpiredTimers(logs, now: now) { setLogs(expired) }
    }

    // MARK: Edits

    private func setLogs(_ newLogs: [DraftExercise]) {
        controller.setLogs(newLogs, userId: userId)
    }

    func updateSet(exIdx: Int, setIdx: Int, field: SetField, value: Double) {
        let (newLogs, pr) = SetEditing.updateSet(logs, exIdx: exIdx, setIdx: setIdx, field: field, value: value,
                                                 prDetector: &prDetector)
        setLogs(newLogs)
        if pr?.shouldFlash == true, newLogs.indices.contains(exIdx), newLogs[exIdx].sets.indices.contains(setIdx) {
            flashId += 1
            let flash = LogPrFlash(id: flashId, exercise: newLogs[exIdx].name, weight: newLogs[exIdx].sets[setIdx].weight)
            prFlashes.append(flash)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.prFlashes.removeAll { $0.id == flash.id }
            }
        }
    }

    func toggleSetDone(exIdx: Int, setIdx: Int) {
        let newLogs = SetEditing.toggleSetDone(logs, exIdx: exIdx, setIdx: setIdx)
        setLogs(newLogs)
        if newLogs[logAt: exIdx]?.sets[logAt: setIdx]?.completed == true { scrollToNextSet() }
    }

    func completeChecklistRound(_ exIdx: Int) { setLogs(SetEditing.completeChecklistRound(logs, exIdx: exIdx)) }
    func toggleChecklistRound(_ exIdx: Int) { setLogs(SetEditing.toggleChecklistRound(logs, exIdx: exIdx)) }
    func updateNotes(_ exIdx: Int, _ notes: String) { setLogs(SetEditing.updateNotes(logs, exIdx: exIdx, notes: notes)) }
    func toggleNotes(_ exIdx: Int) { setLogs(SetEditing.toggleNotes(logs, exIdx: exIdx)) }

    func startTimer(_ exIdx: Int) { now = logNowMs(); setLogs(SessionTimers.startTimer(logs, exIdx: exIdx, now: now)) }
    func pauseTimer(_ exIdx: Int) { now = logNowMs(); setLogs(SessionTimers.pauseTimer(logs, exIdx: exIdx, now: now)) }
    func resetTimer(_ exIdx: Int) { setLogs(SessionTimers.resetTimer(logs, exIdx: exIdx)) }

    // MARK: Finish / cancel

    func handleFinishTap() {
        // Calibration skips the "not every set is logged" gate: the finish sheet is
        // the one step before saving.
        if isCalibration {
            showCalibrationFinish = true
            return
        }
        if LogScreenRules.allItemsComplete(logs) {
            Task { await finishWorkout(note: nil) }
        } else {
            showIncompleteConfirm = true
        }
    }

    /// `note` is the calibration finish sheet's session note; the regular logger
    /// always sends nil.
    func finishWorkout(note: String?) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        let input = SetEditing.buildWorkoutLogInput(
            logs: logs, activeDay: activeDay, programWeekNumber: program?.weekNumber,
            startedAt: controller.startedAt, now: logNowMs(), isCalibration: isCalibration, note: note)
        do {
            try await LogAPI.saveWorkout(client, input)
        } catch {
            // Leave the draft and the user on the page - losing a finished session
            // to a failed request would be far worse than an extra tap on Finish.
            appLog.error("createWorkout failed: \(String(describing: error), privacy: .public)")
            toast(LogToast(title: "Couldn't save your workout", description: "Your session is still here. Please try again.",
                           isError: true))
            return
        }
        let prs = sessionPrCount
        let logged = LogScreenRules.loggedCount(logs)
        let calibration = isCalibration
        controller.endSession(userId: userId)
        showCalibrationFinish = false
        let saved = LogScreenRules.savedToast(isCalibration: calibration, prCount: prs, loggedCount: logged)
        ended(toast: LogToast(title: saved.title, description: saved.description), goTo: .home)
    }

    func cancelWorkout() {
        let calibration = isCalibration
        controller.endSession(userId: userId)
        showCancelConfirm = false
        // Calibration sessions start from the briefing, so a cancel goes to the dashboard.
        ended(toast: nil, goTo: calibration ? .home : .program)
    }

    private func ended(toast: LogToast?, goTo tab: IntentTabBar.Tab) {
        if let launcher {
            launcher.sessionEnded(toast: toast, goTo: tab)
        } else if let toast {
            localToast(toast)
        }
    }

    private func toast(_ t: LogToast) {
        if let launcher { launcher.show(t) } else { localToast(t) }
    }

    /// WorkoutLogLockDialog's "I'm ready - start today".
    func startToday() async {
        guard let program, !startingToday else { return }
        startingToday = true
        defer { startingToday = false }
        do {
            _ = try await client.setProgramStartDate(
                path: .init(id: program.id),
                body: .json(.init(startDate: Calibration.localDateString(Date())))
            ).ok
            self.program = try await LogAPI.program(client)
            sync()
            await launcher?.reloadProgram()
        } catch {
            toast(LogToast(title: "Couldn't update your start date", description: "Please try again.", isError: true))
        }
    }

    // MARK: Hints

    func prevSets(for ex: DraftExercise) -> [LoggedSet]? { lookup.lastSetsByExercise[ex.name.lowercased()] }
    func prevNote(for ex: DraftExercise) -> LastNote? { lookup.lastNoteByExercise[ex.name.lowercased()] }
}


extension Array {
    subscript(logAt index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

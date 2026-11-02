import Foundation
import Testing
@testable import IntentCore

// Hand-written tests for logic that lives in React components/hooks the fixture
// generator can't run headless (log.tsx's handlers, useWorkoutSession's state
// machine), plus subtle cases worth pinning down by name.

private let stockholm = TimeZone(identifier: "Europe/Stockholm")!
private let t0 = 1_792_920_000_000.0 // 2026-10-25T09:20:00Z

private func day(_ n: Int, _ exercises: [Exercise]) -> ProgramDay {
    ProgramDay(dayNumber: n, label: "Day \(n)", focus: "", exercises: exercises)
}

private let bench = Exercise(name: "Bench Press", sets: 2, reps: "6-8", muscle: "Chest")
private let row = Exercise(name: "Single-arm Row", sets: 1, reps: "10", muscle: "Upper Back", isUnilateral: true)
private let plank = Exercise(name: "Plank", sets: 2, reps: "", muscle: "", kind: .checklist, targetType: .duration, targetSeconds: 60)

private func program(id: Int = 7, days: [ProgramDay]) -> Program {
    Program(id: id, weekNumber: 3, aiGenerated: true, days: days, generatedAt: "2026-10-20T10:00:00.000Z")
}

@Suite("Set editing (log.tsx)")
struct SetEditingTests {
    @Test func typingWeightThenRepsCompletesTheSet() {
        var detector = PrDetector(history: [], personalRecords: [])
        var logs = SessionLogs.buildFreshLogs(day(1, [bench]))
        var r = SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .weight, value: 80, prDetector: &detector)
        #expect(r.logs[0].sets[0].completed == false)
        #expect(r.pr == nil)
        logs = r.logs
        r = SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .reps, value: 8, prDetector: &detector)
        #expect(r.logs[0].sets[0].completed)
        // First ever log of an exercise is a baseline, never a PR.
        #expect(r.pr == PrJudgement(isNewPr: false, shouldFlash: false))
    }

    @Test func valuesAreClampedToTheApiBands() {
        var detector = PrDetector(history: [], personalRecords: [])
        let logs = SessionLogs.buildFreshLogs(day(1, [bench]))
        #expect(SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .weight, value: -5, prDetector: &detector).logs[0].sets[0].weight == 0)
        #expect(SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .weight, value: 5000, prDetector: &detector).logs[0].sets[0].weight == 2000)
        #expect(SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .reps, value: 4000, prDetector: &detector).logs[0].sets[0].reps == 1000)
        #expect(SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .reps, value: .nan, prDetector: &detector).logs[0].sets[0].reps == 0)
    }

    @Test func unilateralNeedsBothSides() {
        var detector = PrDetector(history: [], personalRecords: [])
        var logs = SessionLogs.buildFreshLogs(day(1, [row]))
        logs = SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .weight, value: 30, prDetector: &detector).logs
        logs = SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .reps, value: 10, prDetector: &detector).logs
        #expect(logs[0].sets[0].completed == false) // bilateral reps don't count
        logs = SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .repsLeft, value: 10, prDetector: &detector).logs
        #expect(logs[0].sets[0].completed == false)
        logs = SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .repsRight, value: 9, prDetector: &detector).logs
        #expect(logs[0].sets[0].completed)
    }

    @Test func prFlashesOnceAndUnflagsWhenBeaten() {
        let history = [WorkoutLog(date: "2026-10-18", exercisesLogged: [
            LoggedExercise(name: "Bench Press", muscle: "Chest", sets: [LoggedSet(setNumber: 1, weight: 80, reps: 8)]),
        ])]
        var detector = PrDetector(history: history, personalRecords: [])
        var logs = SessionLogs.buildFreshLogs(day(1, [bench]))
        logs = SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .weight, value: 82.5, prDetector: &detector).logs
        let r = SetEditing.updateSet(logs, exIdx: 0, setIdx: 0, field: .reps, value: 8, prDetector: &detector)
        #expect(r.pr == PrJudgement(isNewPr: true, shouldFlash: true))
        #expect(r.logs[0].sets[0].isNewPr)
        // Re-typing the same set: still a PR, but no second toast.
        let again = SetEditing.updateSet(r.logs, exIdx: 0, setIdx: 0, field: .reps, value: 9, prDetector: &detector)
        #expect(again.pr == PrJudgement(isNewPr: true, shouldFlash: false))
        // A second set equal to the session best is not a PR.
        var next = SetEditing.updateSet(again.logs, exIdx: 0, setIdx: 1, field: .weight, value: 82.5, prDetector: &detector).logs
        next = SetEditing.updateSet(next, exIdx: 0, setIdx: 1, field: .reps, value: 8, prDetector: &detector).logs
        #expect(next[0].sets[1].isNewPr == false)
    }

    @Test func updateBaselineKeepsSessionBests() {
        let history = [WorkoutLog(date: "2026-10-18", exercisesLogged: [
            LoggedExercise(name: "Bench Press", muscle: "Chest", sets: [LoggedSet(setNumber: 1, weight: 80, reps: 8)]),
        ])]
        var detector = PrDetector(history: history, personalRecords: [])
        _ = detector.judgeSet(name: "Bench Press", isUnilateral: false, set: SetNumbers(weight: 100, reps: 5), wasPr: false)
        detector.updateBaseline(history: history, personalRecords: [])
        #expect(detector.sessionBest["bench press"] == SessionLogs.estimatedOneRepMax(weight: 100, reps: 5))
    }

    @Test func inputParsing() {
        #expect(SetEditing.parseWeightInput("82.5kg") == 82.5)
        #expect(SetEditing.parseWeightInput("") == 0)
        #expect(SetEditing.parseWeightInput("abc") == 0)
        #expect(SetEditing.parseRepsInput("8.9") == 8)
        #expect(SetEditing.parseRepsInput("0x10") == 16) // parseInt without a radix
        #expect(SetEditing.parseRepsInput("") == 0)
    }

    @Test func checklistRounds() {
        var logs = SessionLogs.buildFreshLogs(day(1, [plank]))
        logs = SessionTimers.startTimer(logs, exIdx: 0, now: t0)
        logs = SetEditing.toggleChecklistRound(logs, exIdx: 0)
        #expect(logs[0].completedRounds == 1 && logs[0].timerEndsAt == nil)
        logs = SetEditing.completeChecklistRound(logs, exIdx: 0)
        logs = SetEditing.completeChecklistRound(logs, exIdx: 0) // capped
        #expect(logs[0].completedRounds == 2)
        logs = SetEditing.toggleChecklistRound(logs, exIdx: 0) // all done -> untick all
        #expect(logs[0].completedRounds == 0)
        logs = SetEditing.toggleNotes(SetEditing.updateNotes(logs, exIdx: 0, notes: "hold longer"), exIdx: 0)
        #expect(logs[0].notes == "hold longer" && logs[0].showNotes)
        #expect(SetEditing.toggleSetDone(SessionLogs.buildFreshLogs(day(1, [bench])), exIdx: 0, setIdx: 1)[0].sets[1].completed)
    }

    @Test func workoutLogInput() {
        var logs = SessionLogs.buildFreshLogs(day(2, [bench, row, plank]))
        logs[0].sets[0] = DraftSet(setNumber: 1, weight: 80, reps: 8, completed: true, isNewPr: true)
        logs[1].sets[0] = DraftSet(setNumber: 1, weight: 30, reps: 99, repsLeft: 10, repsRight: 9, completed: true)
        logs[1].notes = "left weaker"
        logs[2].completedRounds = 1
        logs.append(DraftExercise(name: "   ", muscle: "x"))
        // 23:30 local in Stockholm on Oct 24 is still Oct 24 in UTC; 00:30 local on
        // Oct 25 (22:30Z) is filed as Oct 24 - the web's UTC-date behaviour.
        let finish = 1_792_881_000_000.0 // 2026-10-24T22:30:00Z = 00:30 local on the 25th
        let started = finish - 3_725_400
        let input = SetEditing.buildWorkoutLogInput(logs: logs, activeDay: day(2, []), programWeekNumber: 3, startedAt: started,
                                                    now: finish, isCalibration: false, note: nil)
        #expect(input.date == "2026-10-24")
        #expect(Calibration.localDateString(Date(timeIntervalSince1970: finish / 1000), timeZone: stockholm) == "2026-10-25")
        #expect(input.dayNumber == 2 && input.weekNumber == 3 && input.dayLabel == "Day 2")
        #expect(input.startedAt == "2026-10-24T21:27:54.600Z")
        #expect(input.durationSeconds == 3725)
        #expect(input.exercisesLogged.count == 3)
        #expect(input.exercisesLogged[0].sets[0] == LoggedSet(setNumber: 1, weight: 80, reps: 8, completed: true, isNewPr: true))
        #expect(input.exercisesLogged[0].notes == nil)
        #expect(input.exercisesLogged[1].sets[0] == LoggedSet(setNumber: 1, weight: 30, reps: nil, repsLeft: 10, repsRight: 9, completed: true, isNewPr: false))
        #expect(input.exercisesLogged[1].notes == "left weaker")
        #expect(input.exercisesLogged[2] == LoggedExercise(name: "Plank", muscle: "", sets: [], kind: .checklist, completedRounds: 1, targetSeconds: 60))
        #expect(input.loggingMode == .full)

        let calib = SetEditing.buildWorkoutLogInput(logs: logs, activeDay: nil, programWeekNumber: nil, startedAt: nil,
                                                    now: finish, isCalibration: true, note: "felt fine")
        #expect(calib.exercisesLogged[0].sets[0] == LoggedSet(setNumber: 1, weight: 0, reps: nil, completed: true, isNewPr: false))
        #expect(calib.dayNumber == 1 && calib.weekNumber == 1 && calib.dayLabel == nil)
        #expect(calib.startedAt == nil && calib.durationSeconds == nil)
        #expect(calib.loggingMode == .calibration && calib.notes == "felt fine")
    }
}

@Suite("Session timers")
struct SessionTimerTests {
    @Test func clocksAreDerivedFromTimestamps() {
        #expect(SessionTimers.elapsedSeconds(startedAt: nil, now: t0) == nil)
        #expect(SessionTimers.elapsedSeconds(startedAt: t0, now: t0 + 61_999) == 61)
        var logs = SessionLogs.buildFreshLogs(day(1, [plank]))
        #expect(SessionTimers.isTimed(logs[0]))
        #expect(SessionTimers.remainingSeconds(logs[0], now: t0) == 60)
        logs = SessionTimers.startTimer(logs, exIdx: 0, now: t0)
        #expect(SessionTimers.hasRunningTimer(logs))
        #expect(SessionTimers.remainingSeconds(logs[0], now: t0 + 500) == 60) // ceil
        #expect(SessionTimers.remainingSeconds(logs[0], now: t0 + 59_001) == 1)
        #expect(SessionTimers.completeExpiredTimers(logs, now: t0 + 59_999) == nil)
        logs = SessionTimers.pauseTimer(logs, exIdx: 0, now: t0 + 20_400)
        #expect(logs[0].timerPausedRemaining == 40 && SessionTimers.remainingSeconds(logs[0], now: t0 + 99_999) == 40)
        logs = SessionTimers.startTimer(logs, exIdx: 0, now: t0 + 100_000)
        #expect(logs[0].timerEndsAt == t0 + 140_000)
        // Backgrounded past expiry: the round ticks itself off on the next tick.
        let done = SessionTimers.completeExpiredTimers(logs, now: t0 + 600_000)
        #expect(done?[0].completedRounds == 1 && done?[0].timerEndsAt == nil)
    }
}

@Suite("Workout session controller (useWorkoutSession)")
struct WorkoutSessionControllerTests {
    final class Env {
        let clock = Clock(t0)
        let store = InMemoryKeyValueStore()
        lazy var sessions = WorkoutSessionStore(store: store, now: { [clock] in clock.now })
    }

    @Test func idleWithoutASessionAndWaitingWithoutData() {
        let env = Env()
        var c = WorkoutSessionController(sessions: env.sessions)
        c.sync(program: nil, userId: "u", request: LogRequest())
        #expect(c.hasSession == nil)
        c.sync(program: program(days: [day(1, [bench])]), userId: "u", request: LogRequest(targetDayNumber: 1))
        #expect(c.hasSession == false && c.logs.isEmpty)
    }

    @Test func startRequestBeginsTheSessionAndSpendsTheRequest() {
        let env = Env()
        var c = WorkoutSessionController(sessions: env.sessions)
        let p = program(days: [day(1, [bench]), day(2, [plank])])
        let r = c.sync(program: p, userId: "u", request: LogRequest(query: ["day": "2", "start": "1"]))
        #expect(c.hasSession == true && c.activeDay?.dayNumber == 2)
        #expect(r.redirectPath == "/log?day=2")
        #expect(c.startedAt == t0)
        #expect(c.logs.map(\.name) == ["Plank"])
        #expect(env.sessions.resolveActiveSession(userId: "u")?.pointer == ActiveSessionPointer(programId: 7, dayNumber: 2))
        #expect(c.resumedElsewhere == false && c.startFailed == false)
    }

    @Test func refusedStorageReportsStartFailed() {
        let env = Env()
        env.store.refusesWrites = true
        var c = WorkoutSessionController(sessions: env.sessions)
        c.sync(program: program(days: [day(1, [bench])]), userId: "u", request: LogRequest(targetDayNumber: 1, startRequested: true))
        #expect(c.startFailed && c.hasSession == false)
    }

    @Test func liveSessionWinsOverAnotherDaysStart() {
        let env = Env()
        env.sessions.startSession(userId: "u", programId: 7, dayNumber: 1)
        var c = WorkoutSessionController(sessions: env.sessions)
        let r = c.sync(program: program(days: [day(1, [bench]), day(2, [plank])]), userId: "u",
                       request: LogRequest(targetDayNumber: 2, startRequested: true))
        #expect(c.activeDay?.dayNumber == 1)
        #expect(c.resumedElsewhere)
        #expect(r.redirect == LogRequest(targetDayNumber: 1))
    }

    @Test func bareUrlIsNormalisedWithoutTheBanner() {
        let env = Env()
        env.sessions.startSession(userId: "u", programId: 7, dayNumber: 2)
        var c = WorkoutSessionController(sessions: env.sessions)
        let r = c.sync(program: program(days: [day(1, [bench]), day(2, [plank])]), userId: "u", request: LogRequest())
        #expect(c.activeDay?.dayNumber == 2 && c.resumedElsewhere == false)
        #expect(r.redirectPath == "/log?day=2") // ?day= defaulted to day 1, so it's rewritten
    }

    @Test func sessionOfAnotherProgramIsDropped() {
        let env = Env()
        env.sessions.startSession(userId: "u", programId: 99, dayNumber: 1)
        var c = WorkoutSessionController(sessions: env.sessions)
        c.sync(program: program(days: [day(1, [bench])]), userId: "u", request: LogRequest(targetDayNumber: 1))
        #expect(c.hasSession == false)
        #expect(env.sessions.loadActiveSession(userId: "u") == nil)
    }

    @Test func editsPersistAndAProgramEditReseedsKeepingWork() {
        let env = Env()
        env.sessions.startSession(userId: "u", programId: 7, dayNumber: 1)
        var c = WorkoutSessionController(sessions: env.sessions)
        c.sync(program: program(days: [day(1, [bench])]), userId: "u", request: LogRequest(targetDayNumber: 1))
        var logs = c.logs
        logs[0].sets[0] = DraftSet(setNumber: 1, weight: 80, reps: 8, completed: true)
        env.clock.now += 60_000
        c.setLogs(logs, userId: "u")
        let saved = env.sessions.resolveActiveSession(userId: "u")
        #expect(saved?.draft.logs[0].sets[0].weight == 80)
        #expect(saved?.draft.savedAt == t0 + 60_000 && saved?.draft.startedAt == t0)

        // Same program refetched: nothing re-seeds.
        c.sync(program: program(days: [day(1, [bench])]), userId: "u", request: LogRequest(targetDayNumber: 1))
        #expect(c.logs[0].sets[0].weight == 80)

        // Program edited mid-session: new structure, entered work folded back in.
        c.sync(program: program(days: [day(1, [plank, bench])]), userId: "u", request: LogRequest(targetDayNumber: 1))
        #expect(c.logs.map(\.name) == ["Plank", "Bench Press"])
        #expect(c.logs[1].sets[0].weight == 80)
        #expect(c.startedAt == t0)
    }

    @Test func endingStopsReseedAndClearsStorage() {
        let env = Env()
        env.sessions.startSession(userId: "u", programId: 7, dayNumber: 1)
        var c = WorkoutSessionController(sessions: env.sessions)
        let p = program(days: [day(1, [bench])])
        c.sync(program: p, userId: "u", request: LogRequest(targetDayNumber: 1))
        c.endSession(userId: "u")
        c.setLogs(c.logs, userId: "u")
        c.sync(program: p, userId: "u", request: LogRequest(targetDayNumber: 1))
        #expect(env.store.allValues.isEmpty)
        #expect(c.hasSession == true) // the leaving screen is not flashed to idle
    }

    @Test func draftOlderThanADayIsGone() {
        let env = Env()
        env.sessions.startSession(userId: "u", programId: 7, dayNumber: 1)
        env.clock.now += WorkoutSession.draftMaxAgeMs + 1
        var c = WorkoutSessionController(sessions: env.sessions)
        c.sync(program: program(days: [day(1, [bench])]), userId: "u", request: LogRequest(targetDayNumber: 1))
        #expect(c.hasSession == false)
    }

    @Test func requestParsing() {
        #expect(LogRequest(query: ["day": "3abc"]) == LogRequest(targetDayNumber: 3))
        #expect(LogRequest(query: ["day": "x", "start": "true", "resumed": "1"]) == LogRequest(resumeRequested: true))
    }
}

@Suite("Model decoding")
struct ModelDecodingTests {
    @Test func legacyRowsDecodeLikeTheWebReadsThem() throws {
        let json = #"{"name":"Old Row","sets":3,"reps":"8","muscle":"Chest","targetType":"weird","category":"cardio"}"#
        let ex = try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        #expect(ex.kind == .lift)
        #expect(ex.targetType == nil)
        #expect(ex.category == "cardio" && ChecklistItems.parseCategory(ex.category) == nil)
        let item = try JSONDecoder().decode(Exercise.self, from: Data(#"{"name":"S","sets":1,"reps":"","muscle":"","kind":"checklist"}"#.utf8))
        #expect(item.kind == .checklist)
        let logged = try JSONDecoder().decode(LoggedExercise.self, from: Data(#"{"name":"S","muscle":"","sets":[],"kind":"checklist","category":"nope"}"#.utf8))
        #expect(logged.kind == .checklist && logged.category == nil)
    }
}

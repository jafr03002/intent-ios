import Foundation
import Testing
@testable import IntentCore

@Suite struct LogScreenRulesTests {
    private func lift(_ name: String, sets: [DraftSet], unilateral: Bool = false) -> DraftExercise {
        DraftExercise(name: name, muscle: "Chest", isUnilateral: unilateral, sets: sets, targetSets: sets.count, targetReps: "6-8")
    }

    private func checklist(_ name: String, done: Int, of rounds: Int, category: ChecklistCategory? = .mobility) -> DraftExercise {
        DraftExercise(name: name, muscle: "", kind: .checklist, targetType: .duration, targetSeconds: 60,
                      category: category, completedRounds: done, targetRounds: rounds)
    }

    @Test func numbersPrintLikeJavaScript() {
        #expect(LogScreenRules.formatNumber(82.5) == "82.5")
        #expect(LogScreenRules.formatNumber(80) == "80")
        #expect(LogScreenRules.inputText(0) == "")
        #expect(LogScreenRules.inputText(102.25) == "102.25")
    }

    @Test func finishGateAndPrCounts() {
        let done = DraftSet(setNumber: 1, weight: 80, reps: 8, completed: true)
        let pr = DraftSet(setNumber: 2, weight: 85, reps: 8, completed: true, isNewPr: true)
        let open = DraftSet(setNumber: 3)
        var logs = [lift("Bench", sets: [done, pr]), checklist("Mobility", done: 1, of: 1)]
        #expect(LogScreenRules.allItemsComplete(logs))
        #expect(LogScreenRules.sessionPrCount(logs) == 1)
        #expect(LogScreenRules.finishTitle(prCount: 1) == "Finish · 1 new PR")
        #expect(LogScreenRules.finishTitle(prCount: 2) == "Finish · 2 new PRs")
        #expect(LogScreenRules.finishTitle(prCount: 0) == "Finish workout")
        #expect(LogScreenRules.prBadge(3) == "3 PRs")
        logs[0].sets.append(open)
        #expect(!LogScreenRules.allItemsComplete(logs))
        logs[0].sets.removeLast()
        logs[1].completedRounds = 0
        #expect(!LogScreenRules.allItemsComplete(logs))
    }

    @Test func savedToastCopy() {
        #expect(LogScreenRules.savedToast(isCalibration: true, prCount: 2, loggedCount: 5).title == "Session saved")
        #expect(LogScreenRules.savedToast(isCalibration: false, prCount: 2, loggedCount: 5).description == "2 new PRs! Nice work.")
        #expect(LogScreenRules.savedToast(isCalibration: false, prCount: 0, loggedCount: 1).description == "1 exercise logged.")
        #expect(LogScreenRules.savedToast(isCalibration: false, prCount: 0, loggedCount: 6).description == "6 exercises logged.")
        let blank = [DraftExercise(name: "  ", muscle: ""), lift("Row", sets: [])]
        #expect(LogScreenRules.loggedCount(blank) == 1)
    }

    @Test func targetsHideForFirstTimers() {
        #expect(!LogScreenRules.showTargets(isIndependent: false, historyCount: nil))
        #expect(!LogScreenRules.showTargets(isIndependent: false, historyCount: 0))
        #expect(LogScreenRules.showTargets(isIndependent: false, historyCount: 3))
        #expect(LogScreenRules.showTargets(isIndependent: true, historyCount: nil))
    }

    @Test func exerciseCardCopy() {
        let ex = lift("Split Squat", sets: [DraftSet(setNumber: 1)], unilateral: true)
        #expect(LogScreenRules.exerciseMeta(ex, showTargets: true, calibration: false) == "Chest · Unilateral · 1 × 6-8")
        #expect(LogScreenRules.exerciseMeta(ex, showTargets: false, calibration: false) == "Chest · Unilateral")
        #expect(LogScreenRules.exerciseMeta(ex, showTargets: false, calibration: true) == "Chest · Unilateral · 1 × 6-8")
        #expect(LogScreenRules.calibrationGuide(ex) == "6-8 reps / side")
        #expect(LogScreenRules.notesButtonTitle(notes: "x", hasPrevNote: true) == "Note saved")
        #expect(LogScreenRules.notesButtonTitle(notes: "", hasPrevNote: true) == "Add a new note")
        #expect(LogScreenRules.notesButtonTitle(notes: "", hasPrevNote: false) == "Add note")
        let utc = TimeZone(identifier: "UTC")!
        #expect(LogScreenRules.lastNotePrefix(LastNote(text: "t", date: "2026-10-26"), timeZone: utc) == "Last session · 26 Oct: ")
        #expect(LogScreenRules.lastNotePrefix(LastNote(text: "t", date: nil)) == "Last session: ")
        let target = SetTarget(weight: 102.5, reps: 5, change: .weight, delta: "+2.5 kg")
        #expect(LogScreenRules.targetText(target, weightUnit: "kg", isUnilateral: true) == "102.5 kg × 5 / side")
    }

    @Test func checklistCopy() {
        let item = checklist("Plank", done: 1, of: 2, category: .core)
        #expect(LogScreenRules.roundLabel(completedRounds: 1, targetRounds: 2) == "round 2 of 2")
        #expect(LogScreenRules.roundLabel(completedRounds: 2, targetRounds: 2) == "round 2 of 2")
        #expect(LogScreenRules.roundLabel(completedRounds: 0, targetRounds: 1) == nil)
        #expect(LogScreenRules.checklistLabel(item) == "Core")
        #expect(LogScreenRules.checklistAccent(item) == .chart2)
        #expect(LogScreenRules.checklistLabel(checklist("x", done: 0, of: 1, category: nil)) == "Checklist")
        #expect(LogScreenRules.checklistTickLabel(item) == "Plank — mark round 2 of 2 done")
        #expect(LogScreenRules.checklistTickLabel(checklist("Plank", done: 2, of: 2)) == "Plank — done, tap to clear")
        #expect(LogScreenRules.timedFillFraction(remaining: 15, total: 60) == 0.75)
        #expect(LogScreenRules.timedFillFraction(remaining: 0, total: 0) == 0)
    }

    @Test func startPickerRowsAndRouting() {
        let day = ProgramDay(dayNumber: 2, label: "", focus: "Legs", exercises: [
            Exercise(name: "Squat", sets: 3, reps: "5", muscle: "Quads"),
            Exercise(name: "Curl", sets: 1, reps: "10", muscle: "Hamstrings"),
            Exercise(name: "Plank", sets: 2, reps: "0:45", muscle: "", kind: .checklist),
        ])
        let row = LogScreenRules.startMenuRow(day)
        #expect(row.title == "Legs")
        #expect(row.subtitle == "2 exercises · 4 sets")
        let one = LogScreenRules.startMenuRow(ProgramDay(dayNumber: 1, label: "A", exercises: [Exercise(name: "x", sets: 1, reps: "1", muscle: "")]))
        #expect(one.subtitle == "1 exercise · 1 set")

        let today = Date(timeIntervalSince1970: 1_793_000_000) // 2026-10-26
        let utc = TimeZone(identifier: "UTC")!
        #expect(LogScreenRules.startPress(program: nil, today: today) == .goToProgram)
        var program = Program(id: 1, aiGenerated: true, days: [day], generatedAt: "", shortTermPhase: .calibration, startDate: "2026-10-20")
        #expect(LogScreenRules.startPress(program: program, today: today, timeZone: utc) == .openPicker)
        #expect(LogScreenRules.pickRoute(program: program, dayNumber: 2) == .briefing(dayNumber: 2))
        #expect(!CalibrationBriefing.shouldSkipBriefing(program, today: today, timeZone: utc))
        program.startDate = "2026-12-01"
        #expect(LogScreenRules.startPress(program: program, today: today, timeZone: utc) == .goToProgram)
        #expect(CalibrationBriefing.shouldSkipBriefing(program, today: today, timeZone: utc))
        program.shortTermPhase = .bulk
        program.startDate = nil
        #expect(LogScreenRules.pickRoute(program: program, dayNumber: 2) == .startSession(dayNumber: 2))
        program.days = []
        #expect(LogScreenRules.startPress(program: program, today: today) == .goToProgram)
    }

    @Test func briefingCopy() {
        #expect(CalibrationBriefing.stepCount == 6)
        #expect(CalibrationBriefing.eyebrow(dayLabel: "Upper A") == "Calibration · Upper A")
        #expect(CalibrationBriefing.eyebrow(dayLabel: nil) == "Calibration")
        #expect(!CalibrationBriefing.points.contains { $0.body.contains("3 weeks") })
    }

    @Test func activeSessionSummaryReadsAndSelfHeals() {
        let kv = InMemoryKeyValueStore()
        var clock = 1_000_000.0
        var changes = 0
        let store = WorkoutSessionStore(store: kv, now: { clock }, onActiveSessionChange: { changes += 1 })
        #expect(store.activeSessionSummary(userId: "u") == nil)
        #expect(store.activeSessionSummary(userId: nil) == nil)
        #expect(store.startSession(userId: "u", programId: 12, dayNumber: 2))
        #expect(store.activeSessionSummary(userId: "u") == ActiveSessionSummary(programId: 12, dayNumber: 2, startedAt: 1_000_000))
        clock += WorkoutSession.draftMaxAgeMs + 1
        let before = changes
        #expect(store.activeSessionSummary(userId: "u") == nil)
        #expect(changes == before + 1) // the stale pointer was cleared
        #expect(kv.string(forKey: WorkoutSession.activeSessionKey(userId: "u")) == nil)
    }
}

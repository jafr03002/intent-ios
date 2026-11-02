import Foundation
import Testing
@testable import IntentCore

// Hand-written tests for the program builder and program-page logic ported from
// pages/program/shared.tsx and components/onboarding/PresentationDeck.tsx (React
// component code the fixture generator can't run headless).

private func lift(_ name: String, sets: Int = 3, reps: String = "8-10", muscle: String = "Chest",
                  secondary: String? = nil) -> Exercise {
    Exercise(name: name, sets: sets, reps: reps, muscle: muscle, secondaryMuscle: secondary, kind: .lift)
}

private let stretch = Exercise(name: "Couch stretch", sets: 2, reps: "2:30", muscle: "", kind: .checklist,
                               targetType: .duration, targetSeconds: 150, category: "mobility")

private func program(_ days: [ProgramDay], name: String = "My PPL") -> Program {
    var p = Program(id: 9, programName: name, splitType: "custom", aiGenerated: false, days: days,
                    generatedAt: "2026-10-20T10:00:00.000Z")
    p.weekNumber = 3
    return p
}

@Suite("Program builder (shared.tsx)")
struct ProgramBuilderTests {
    @Test func newRowsMatchTheWebDefaults() {
        let ex = ProgramBuilder.newExercise()
        #expect(ex.sets == "2" && ex.reps == "8-12" && ex.kind == .lift && ex.targetUnit == "m")
        let item = ProgramBuilder.newChecklistItem()
        #expect(item.sets == "1" && item.reps == "" && item.kind == .checklist && item.targetType == TargetType.none)
        #expect(ProgramBuilder.blankDays().count == 1)
    }

    @Test func editDaysRoundTripsAProgram() {
        var long = stretch
        long.targetSeconds = 99_999
        let days = ProgramBuilder.editDays(from: [ProgramDay(dayNumber: 1, label: "Push", exercises: [
            lift("Bench", secondary: "Triceps"), long,
        ])])
        #expect(days[0].label == "Push")
        #expect(days[0].exercises[0].secondaryMuscle == "Triceps")
        #expect(days[0].exercises[0].sets == "3")
        #expect(days[0].exercises[1].kind == .checklist)
        #expect(days[0].exercises[1].durationSeconds == ChecklistItems.maxWheelSeconds)
        #expect(days[0].exercises[1].category == "mobility")
    }

    @Test func findInvalidFieldReportsOneFieldAtATime() {
        var days = [ProgramEditDay(label: "", exercises: [ProgramBuilder.newExercise()])]
        #expect(ProgramBuilder.findInvalidField(days)?.field == .label)
        days[0].label = "Push"
        let nameError = ProgramBuilder.findInvalidField(days)
        #expect(nameError?.field == .name && nameError?.exercise == 0)
        #expect(nameError?.message == ProgramBuilder.missingFieldMessage)
        days[0].exercises[0].name = "Bench"
        days[0].exercises[0].sets = ""
        #expect(ProgramBuilder.findInvalidField(days)?.message == "Enter a set count between 1 and 50.")
        days[0].exercises[0].sets = "0"
        #expect(ProgramBuilder.findInvalidField(days)?.message == "Enter a set count between 1 and 50.")
        days[0].exercises[0].sets = "2.5"
        #expect(ProgramBuilder.findInvalidField(days)?.message == "Enter your set count as a whole number.")
        days[0].exercises[0].sets = "4"
        #expect(ProgramBuilder.findInvalidField(days) == nil)
    }

    @Test func checklistItemsOnlyNeedAName() {
        var item = ProgramBuilder.newChecklistItem()
        item.name = "Plank"
        item.sets = ""
        let days = [ProgramEditDay(label: "Core", exercises: [item])]
        #expect(ProgramBuilder.findInvalidField(days) == nil)
        var bad = days
        bad[0].exercises[0].sets = "99"
        #expect(ProgramBuilder.findInvalidField(bad)?.field == .sets)
    }

    @Test func draftChangesIgnoreWhitespaceAndChecklistFields() {
        let saved = program([ProgramDay(dayNumber: 1, label: "Push", exercises: [lift("Bench"), stretch])])
        var days = ProgramBuilder.editDays(from: saved.days)
        let same = ProgramDraft(programName: "My PPL ", days: days, savedAt: 0)
        #expect(!ProgramBuilder.draftHasChanges(same, programName: saved.programName, days: saved.days))
        // Ported web bug: a checklist-only change is not "unsaved work".
        days[0].exercises[1].durationSeconds = 30
        days[0].exercises[1].category = "core"
        let checklistOnly = ProgramDraft(programName: "My PPL", days: days, savedAt: 0)
        #expect(!ProgramBuilder.draftHasChanges(checklistOnly, programName: saved.programName, days: saved.days))
        days[0].exercises[0].reps = "5"
        let real = ProgramDraft(programName: "My PPL", days: days, savedAt: 0)
        #expect(ProgramBuilder.draftHasChanges(real, programName: saved.programName, days: saved.days))
        #expect(!ProgramBuilder.draftHasChanges(nil, programName: nil, days: nil))
        let blank = ProgramDraft(programName: "", days: ProgramBuilder.blankDays(), savedAt: 0)
        #expect(!ProgramBuilder.draftHasChanges(blank, programName: nil, days: nil))
    }

    @Test func draftsExpireAfterADay() {
        let d = ProgramDraft(programName: "x", days: [], savedAt: 1_000)
        #expect(ProgramBuilder.freshDraft(d, nowMs: 1_000 + ProgramBuilder.draftMaxAgeMs) != nil)
        #expect(ProgramBuilder.freshDraft(d, nowMs: 1_001 + ProgramBuilder.draftMaxAgeMs) == nil)
        #expect(ProgramBuilder.draftKey(userId: "u1", programId: nil) == "traintent:program-draft:u1:new")
        #expect(ProgramBuilder.draftKey(userId: "u1", programId: 9) == "traintent:program-draft:u1:9")
    }

    @Test func draftsSurviveJSON() throws {
        let days = ProgramBuilder.editDays(from: [ProgramDay(dayNumber: 1, label: "Push", exercises: [lift("Bench"), stretch])])
        let draft = ProgramDraft(programName: "P", days: days, savedAt: 5)
        let back = try JSONDecoder().decode(ProgramDraft.self, from: JSONEncoder().encode(draft))
        #expect(back == draft)
    }

    @Test func saveMappingMatchesPerformSave() {
        var chk = ProgramBuilder.newChecklistItem()
        chk.name = " Plank "
        chk.sets = "3"
        chk.targetType = .duration
        chk.durationSeconds = 45
        chk.category = "core"
        var count = ProgramBuilder.newChecklistItem()
        count.name = "Band pull-aparts"
        count.sets = ""
        count.targetType = .count
        count.targetValue = "20"
        var run = ProgramBuilder.newChecklistItem()
        run.name = "Row"
        run.targetType = .distance
        run.targetValue = "500"
        run.targetUnit = "m"
        var bench = ProgramBuilder.newExercise()
        bench.name = "Bench"
        bench.sets = "4"
        bench.muscle = "Chest"
        let out = ProgramBuilder.programDays([ProgramEditDay(label: " Push ", exercises: [bench, chk, count, run])])
        #expect(out[0].dayNumber == 1 && out[0].label == "Push" && out[0].focus == "Push")
        let e = out[0].exercises
        #expect(e[0].sets == 4 && e[0].kind == .lift && e[0].secondaryMuscle == nil && e[0].isUnilateral == false)
        #expect(e[1].name == "Plank" && e[1].sets == 3 && e[1].reps == "0:45" && e[1].targetSeconds == 45)
        #expect(e[1].targetUnit == nil && e[1].category == "core" && e[1].muscle == "")
        #expect(e[2].sets == 1 && e[2].reps == "× 20" && e[2].targetValue == 20 && e[2].targetUnit == "reps")
        #expect(e[2].targetSeconds == nil && e[2].category == nil)
        #expect(e[3].reps == "500 m" && e[3].targetUnit == "m")
        #expect(ProgramBuilder.saveName("") == "My Program")
        #expect(ProgramBuilder.saveSplitType(nil) == "Custom")
        #expect(ProgramBuilder.saveSplitType("custom") == "custom")
    }

    @Test func unsetMuscleSkipsChecklistAndUnnamedRows() {
        var a = ProgramBuilder.newExercise()
        var c = ProgramBuilder.newChecklistItem()
        c.name = "Stretch"
        #expect(!ProgramBuilder.hasUnsetMuscle([ProgramEditDay(label: "x", exercises: [a, c])]))
        a.name = "Bench"
        #expect(ProgramBuilder.hasUnsetMuscle([ProgramEditDay(label: "x", exercises: [a, c])]))
    }

    @Test func stateEditsAndErrorClearing() {
        var s = ProgramBuilderState(draft: nil, editing: nil)
        let ok = s.validateForSave()
        #expect(!ok)
        #expect(s.fieldError?.field == .label)
        s.setDayLabel(0, "Push")
        #expect(s.fieldError == nil)
        let ok2 = s.validateForSave()
        #expect(!ok2)
        #expect(s.fieldError?.field == .name)
        s.patchExercise(0, 0) { $0.name = "Bench"; $0.muscle = "Chest" }
        #expect(s.fieldError == nil)
        s.addChecklistItem(0)
        s.addDay()
        #expect(s.days.count == 2 && s.days[0].exercises.count == 2)
        s.moveExercise(0, 1, by: -1)
        #expect(s.days[0].exercises[0].kind == .checklist)
        s.moveExercise(0, 0, by: -1) // no-op at the top
        #expect(s.days[0].exercises[0].kind == .checklist)
        s.setDayLabel(1, "Pull")
        s.moveDay(from: 1, to: 0)
        #expect(s.days.map(\.label) == ["Pull", "Push"])
        s.setTargetType(1, 0, .duration)
        s.patchExercise(1, 0) { $0.durationSeconds = 90 }
        s.setTargetType(1, 0, .count)
        #expect(s.days[1].exercises[0].durationSeconds == 0)
        s.removeDay(0)
        #expect(s.days.count == 1)
    }

    @Test func restoredDraftCarriesItsErrorFlag() {
        let draft = ProgramDraft(programName: "", days: [ProgramEditDay(label: "", exercises: [])], savedAt: 0)
        #expect(ProgramBuilderState(draft: draft, editing: nil).fieldError?.field == .label)
    }
}

@Suite("Program page + deck")
struct ProgramPresentationTests {
    let day = ProgramDay(dayNumber: 1, label: "Upper A", focus: "Chest & back",
                         estimatedDurationMinutes: 62, exercises: [
                             lift("Bench", sets: 4, reps: "6-8", secondary: "Triceps"),
                             lift("Row", sets: 4, reps: "8", muscle: "Upper Back"),
                             stretch,
                         ])

    @Test func heroCountsLiftsOnly() {
        #expect(ProgramWeek.liftExercises(day).count == 2)
        #expect(ProgramWeek.totalSets(day) == 8)
        #expect(ProgramWeek.rosterTrailing(day.exercises[0]) == "4 × 6-8")
        #expect(ProgramWeek.rosterTrailing(stretch) == "2 × 2:30")
        #expect(ProgramWeek.rosterMuscles(day.exercises[0]) == "Chest · Triceps")
        #expect(ProgramWeek.rosterMuscles(lift("X", muscle: "")) == "—")
    }

    @Test func sessionDurationNeedsEnoughSamples() {
        let few = [DayDurationStat(dayLabel: "Upper A", dayNumber: 9, averageSeconds: 3480, sampleCount: 2)]
        #expect(ProgramWeek.sessionDuration(day, stats: few) == nil)
        let enough = [DayDurationStat(dayLabel: "Upper A", dayNumber: 9, averageSeconds: 3480, sampleCount: 3)]
        #expect(ProgramWeek.sessionDuration(day, stats: enough) == "58m")
        let byNumber = [DayDurationStat(dayLabel: nil, dayNumber: 1, averageSeconds: 3900, sampleCount: 5)]
        #expect(ProgramWeek.sessionDuration(day, stats: byNumber) == "1h 05m")
        let otherLabel = [DayDurationStat(dayLabel: "Lower A", dayNumber: 1, averageSeconds: 3900, sampleCount: 5)]
        #expect(ProgramWeek.sessionDuration(day, stats: otherLabel) == nil)
    }

    @Test func muscleKeysNormalise() {
        #expect(ProgramPresentation.muscleKey("upperBack") == "upper back")
        #expect(ProgramPresentation.muscleKey(" Upper   Back ") == "upper back")
        #expect(ProgramPresentation.muscleLabel("upperBack") == "Upper back")
        #expect(ProgramPresentation.joinWithAnd(["chest", "shoulders", "arms"]) == "chest, shoulders and arms")
        #expect(ProgramPresentation.joinWithAnd(["chest"]) == "chest")
    }

    @Test func weeklyVolumeSkipsChecklistAndSortsDescending() {
        let v = ProgramPresentation.weeklyVolume([day, ProgramDay(dayNumber: 2, label: "B", exercises: [
            lift("Pulldown", sets: 3, muscle: "upperBack"),
        ])])
        #expect(v == [MuscleVolume(muscle: "upper back", sets: 7), MuscleVolume(muscle: "chest", sets: 4)])
    }

    @Test func timelineAndCurrentPhase() {
        let bulk = ProgramPresentation.timeline(goal: "gain_weight")
        #expect(bulk.map(\.phase) == ["calibration", "bulk"])
        #expect(ProgramPresentation.currentPhaseIndex(bulk, shortTermPhase: "deload", goal: "gain_weight") == 1)
        #expect(ProgramPresentation.currentPhaseIndex(bulk, shortTermPhase: nil, goal: "gain_weight") == 0)
        #expect(ProgramPresentation.timeline(goal: "lose_weight").count == 4)
        #expect(ProgramPresentation.timeline(goal: "").last?.phase == "maintenance")
        #expect(ProgramPresentation.goalWeek(goal: "lose_weight") == 22)
    }

    @Test func weekFromScheduleUsesFixedSlots() {
        var p = program([day, ProgramDay(dayNumber: 2, label: "Lower A", exercises: [])])
        p.schedule = ProgramSchedule(mode: .fixed, slots: [1, nil, 2, nil, nil, nil, nil])
        #expect(ProgramPresentation.weekFromSchedule(p).map { $0?.label } == ["Upper A", nil, "Lower A", nil, nil, nil, nil])
        p.schedule = nil
        #expect(ProgramPresentation.weekFromSchedule(p).map { $0?.label } == ["Upper A", "Lower A", nil, nil, nil, nil, nil])
    }

    @Test func textHelpers() {
        #expect(ProgramPresentation.durationText([day]) == "an hour")
        var short = day
        short.estimatedDurationMinutes = 43
        #expect(ProgramPresentation.durationText([short]) == "45 minutes")
        #expect(ProgramPresentation.durationText([ProgramDay(dayNumber: 1, label: "x", exercises: [])]) == nil)
        #expect(ProgramPresentation.splitPhrase("upper_lower") == "upper lower")
        #expect(ProgramPresentation.splitPhrase("Push/Pull, legs") == "push / pull / legs")
        // Ported web quirk: an empty part reads "undefined".
        #expect(ProgramPresentation.splitPhrase("upper/") == "upper / undefined")
        #expect(ProgramPresentation.numberWord(4) == "four" && ProgramPresentation.numberWord(9) == "9")
        var p = program([day])
        p.programHighlights = [ProgramHighlight(title: "Calibration first", detail: "x"),
                               ProgramHighlight(title: "Bench", detail: "y")]
        #expect(ProgramPresentation.highlights(p).map(\.title) == ["Bench"])
    }
}

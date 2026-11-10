import Foundation
import Testing
@testable import IntentCore

// Hand-written tests for the onboarding page's rules (pages/onboarding.tsx) and the
// post-generation deck (components/onboarding/*), which live in React components
// the fixture generator can't run. Expected values were worked out from the TS.

@Suite("Onboarding form (onboarding.tsx)")
struct OnboardingFormTests {
    @Test func stepsPerMode() {
        #expect(OnboardingOptions.steps(for: "").map(\.rawValue) == ["mode", "name", "bodyStats", "goal", "targets", "review"])
        #expect(OnboardingOptions.steps(for: "ai").count == 12)
        #expect(OnboardingOptions.steps(for: "ai").last == .review)
        #expect(OnboardingOptions.steps(for: "independent").contains(.targets))
        #expect(!OnboardingOptions.steps(for: "ai").contains(.targets))
    }

    @Test func suggestedCalories() {
        #expect(OnboardingOptions.suggestCalories(weight: "80", weightUnit: "kg", goal: "gain_weight") == 2700)
        #expect(OnboardingOptions.suggestCalories(weight: "80", weightUnit: "kg", goal: "lose_weight") == 2000)
        #expect(OnboardingOptions.suggestCalories(weight: "", weightUnit: "kg", goal: "general") == 2250)
        // 176 lbs = 79.83 kg -> 2394.9 -> 2400
        #expect(OnboardingOptions.suggestCalories(weight: "176", weightUnit: "lbs", goal: "general") == 2400)
        #expect(OnboardingOptions.suggestCalories(weight: "1500", weightUnit: "kg", goal: "general") == 5000)
        #expect(OnboardingOptions.suggestCalories(weight: "20", weightUnit: "kg", goal: "lose_weight") == 1200)
    }

    @Test func goalWeightConflicts() {
        func conflict(_ goal: String, _ w: String, _ g: String) -> String? {
            OnboardingForm.goalWeightConflict(goal: goal, weight: w, goalWeight: g, weightUnit: "kg")
        }
        #expect(conflict("general", "80", "70") == nil)
        #expect(conflict("gain_weight", "80", "") == nil)
        #expect(conflict("gain_weight", "", "90") == nil)
        #expect(conflict("gain_weight", "80", "90") == nil)
        #expect(conflict("gain_weight", "80", "-50") == "Enter a goal weight between 20 and 1,000.")
        #expect(conflict("gain_weight", "80", "80") == "That's your current weight (80 kg), so there's nothing to reach. Enter a target above it, or pick General fitness instead.")
        #expect(conflict("gain_weight", "80", "75.5") == "You picked Gain weight, but 75.5 kg is below your current 80 kg - that's losing weight. Enter a target above 80 kg, or switch your goal to Lose weight.")
        #expect(conflict("lose_weight", "80", "85") == "You picked Lose weight, but 85 kg is above your current 80 kg - that's gaining weight. Enter a target below 80 kg, or switch your goal to Gain weight.")
    }

    @Test func canAdvanceRules() {
        var f = OnboardingForm()
        #expect(!f.canAdvance(from: .mode))
        f.mode = "ai"
        #expect(f.canAdvance(from: .mode))
        #expect(f.canAdvance(from: .name))
        f.age = "9"
        #expect(!f.canAdvance(from: .bodyStats))
        f.age = "28"
        #expect(f.canAdvance(from: .bodyStats))
        #expect(!f.canAdvance(from: .goal))
        f.selectGoal("general")
        #expect(f.canAdvance(from: .goal))
        #expect(!f.canAdvance(from: .equipment))
        f.toggleEquipment("Dumbbells only")
        #expect(f.canAdvance(from: .equipment))
    }

    @Test func restDayLimit() {
        var f = OnboardingForm()
        f.trainingDays = 5
        #expect(f.maxPreferredRestDays == 3)
        for d in ["mon", "tue", "wed"] { f.togglePreferredRestDay(d) }
        #expect(!f.tooManyPreferredRestDays)
        f.togglePreferredRestDay("thu")
        #expect(f.tooManyPreferredRestDays)
        #expect(!f.canAdvance(from: .preferredRestDays))
        f.togglePreferredRestDay("mon")
        #expect(f.preferredRestDays == ["tue", "wed", "thu"])
    }

    @Test func fullGymIsExclusive() {
        var f = OnboardingForm()
        f.toggleEquipment("Dumbbells only")
        f.toggleEquipment("Pull-up bar")
        f.toggleEquipment("Full gym")
        #expect(f.equipment == ["Full gym"])
        f.toggleEquipment("Cable machines")
        #expect(f.equipment == ["Cable machines"])
        f.toggleEquipment("Full gym")
        f.toggleEquipment("Full gym")
        #expect(f.equipment.isEmpty)
    }

    @Test func musclesCapAtThree() {
        var f = OnboardingForm()
        for m in ["Chest", "Lats", "Quads", "Glutes"] { f.toggleMuscle(m) }
        #expect(f.priorityMuscles == ["Chest", "Lats", "Quads"])
        f.toggleMuscle("No preference")
        #expect(f.priorityMuscles == ["No preference"])
        #expect(f.selectedMuscleCount == 0)
        f.toggleMuscle("Core")
        #expect(f.priorityMuscles == ["Core"])
        #expect(OnboardingOptions.muscles.count == 12)
    }

    @Test func generalFitnessClearsGoalWeight() {
        var f = OnboardingForm()
        f.goalWeight = "90"
        f.selectGoal("gain_weight")
        #expect(f.goalWeight == "90")
        f.selectGoal("general")
        #expect(f.goalWeight == "")
    }

    @Test func clearingInjuriesClearsSeverity() {
        var f = OnboardingForm()
        f.setInjuries("knee")
        f.toggleInjurySeverity("medium")
        #expect(f.payloadInjurySeverity == "medium")
        f.setInjuries("")
        #expect(f.injurySeverity == "")
        #expect(f.payloadInjurySeverity == nil)
    }

    @Test func seedTargetsOnlyFillsBlanks() {
        var f = OnboardingForm()
        f.weight = "80"; f.goal = "gain_weight"
        f.dailyStepTarget = "12000"
        f.seedTargets()
        #expect(f.dailyCalorieTarget == "2700")
        #expect(f.dailyStepTarget == "12000")
    }

    @Test func reviewRowsIndependent() {
        var f = OnboardingForm()
        f.mode = "independent"; f.name = "Sam"; f.goal = "lose_weight"; f.goalWeight = "72"
        f.weight = "80"; f.dailyCalorieTarget = "2000"; f.dailyStepTarget = "10000"
        f.cardioDays = ["Fri", "Mon"]; f.cardioMinutes = "25"
        let rows = f.reviewRows.map { "\($0.label)=\($0.value)" }
        #expect(rows == [
            "Mode=Independent", "Name=Sam", "Goal=Lose weight", "Goal weight=72 kg", "Weight=80 kg",
            "Calorie target=2,000 kcal/day", "Step target=10,000 steps/day", "Cardio=Mon, Fri · 25 min each",
        ])
    }

    @Test func reviewRowsAI() {
        var f = OnboardingForm()
        f.mode = "ai"; f.goal = "general"; f.experience = "intermediate"; f.activityLevel = "high"
        f.preferredRestDays = ["sun", "wed"]; f.equipment = ["Full gym"]; f.sex = "male"
        f.priorityMuscles = ["Chest"]; f.dailyCalorieTarget = "2000"
        let rows = f.reviewRows.map { "\($0.label)=\($0.value)" }
        #expect(rows == [
            "Mode=AI Coach", "Goal=General fitness", "Experience=Intermediate", "Activity level=High",
            "Training days=4 days/week", "Rest days=Sun, Wed", "Equipment=Full gym", "Sex=male", "Priority muscles=Chest",
        ])
    }

    @Test func resumeFromAnUnfinishedProfile() {
        #expect(OnboardingForm.shouldResume(mode: "ai", goal: "general", experience: ""))
        #expect(!OnboardingForm.shouldResume(mode: "ai", goal: "general", experience: "beginner"))
        #expect(!OnboardingForm.shouldResume(mode: "independent", goal: "", experience: ""))
        var f = OnboardingForm()
        f.resume(name: nil, age: 30, sex: "female", weight: 80, weightUnit: nil, goal: "lose_weight", goalWeight: 72.5)
        #expect(f.mode == "ai")
        #expect(f.weight == "80")
        #expect(f.goalWeight == "72.5")
        #expect(f.age == "30")
        #expect(f.weightUnit == "kg")
        let index = OnboardingOptions.steps(for: f.mode).firstIndex(of: .goal)
        #expect(index == 3)
    }

    @Test func payloadNumbers() {
        #expect(OnboardingForm.intOrNil("") == nil)
        #expect(OnboardingForm.intOrNil("28.9") == 28)
        #expect(OnboardingForm.intOrNil("abc") == nil)
        #expect(OnboardingForm.doubleOrNil("80.5") == 80.5)
        var f = OnboardingForm()
        f.cardioMinutes = "30"
        #expect(f.payloadCardioMinutes == nil)
        f.cardioDays = ["Mon"]
        #expect(f.payloadCardioMinutes == 30)
    }
}

@Suite("Presentation deck (PresentationDeck.tsx)")
struct PresentationDeckTests {
    private func day(_ n: Int, _ label: String, minutes: Int? = nil, _ ex: [Exercise]) -> ProgramDay {
        ProgramDay(dayNumber: n, label: label, focus: "", estimatedDurationMinutes: minutes, exercises: ex)
    }

    @Test func wording() {
        #expect(PresentationDeck.numberWord(4) == "four")
        #expect(PresentationDeck.numberWord(9) == "9")
        #expect(PresentationDeck.muscleKey("upperBack") == "upper back")
        #expect(PresentationDeck.muscleKey("  Upper   Back ") == "upper back")
        #expect(PresentationDeck.muscleLabel("Upper Back") == "Upper back")
        #expect(PresentationDeck.joinWithAnd([]) == "")
        #expect(PresentationDeck.joinWithAnd(["chest"]) == "chest")
        #expect(PresentationDeck.joinWithAnd(["chest", "lats", "quads"]) == "chest, lats and quads")
        #expect(PresentationDeck.splitText("upper_lower") == "upper lower")
        #expect(PresentationDeck.splitText("Upper/Lower") == "upper / lower")
        // Ported web bug: an empty segment formats to the literal "undefined".
        #expect(PresentationDeck.splitText("Upper/") == "upper / undefined")
    }

    @Test func timelinePerGoal() {
        #expect(PresentationDeck.timeline(goal: "gain_weight").map(\.phase) == ["calibration", "bulk"])
        #expect(PresentationDeck.timeline(goal: "lose_weight").map(\.phase) == ["calibration", "mini_cut", "deload", "diet"])
        #expect(PresentationDeck.timeline(goal: "general").map(\.phase) == ["calibration", "maintenance"])
        #expect(PresentationDeck.timeline(goal: "general")[0].weeks == "First")
        let gain = PresentationDeck.timeline(goal: "gain_weight")
        #expect(PresentationDeck.currentIndex(gain, shortTermPhase: "deload", goal: "gain_weight") == 1)
        #expect(PresentationDeck.currentIndex(gain, shortTermPhase: "calibration", goal: "gain_weight") == 0)
        #expect(PresentationDeck.currentIndex(gain, shortTermPhase: nil, goal: "gain_weight") == 0)
    }

    @Test func volumeAndDuration() {
        let days = [
            day(1, "Upper", minutes: 60, [
                Exercise(name: "Bench", sets: 3, reps: "8", muscle: "Chest"),
                Exercise(name: "Row", sets: 3, reps: "8", muscle: "upperBack"),
                Exercise(name: "Plank", sets: 2, reps: "", muscle: "", kind: .checklist),
            ]),
            day(2, "Lower", minutes: 45, [
                Exercise(name: "Squat", sets: 4, reps: "6", muscle: "Quads"),
                Exercise(name: "Pulldown", sets: 3, reps: "10", muscle: "Upper Back"),
            ]),
        ]
        let v = PresentationDeck.weeklyVolume(days)
        #expect(v == [.init(muscle: "upper back", sets: 6), .init(muscle: "quads", sets: 4), .init(muscle: "chest", sets: 3)])
        #expect(PresentationDeck.durationText(days) == "an hour")
        #expect(PresentationDeck.durationText([day(1, "A", minutes: 42, [])]) == "40 minutes")
        #expect(PresentationDeck.durationText([day(1, "A", [])]) == nil)
    }

    @Test func weekFromSchedule() {
        let days = [day(1, "A", []), day(2, "B", [])]
        var p = Program(id: 1, aiGenerated: true, days: days, generatedAt: "x",
                        schedule: ProgramSchedule(mode: .fixed, slots: [1, nil, 2, nil, nil, nil, nil]))
        #expect(PresentationDeck.week(p).map { $0?.label } == ["A", nil, "B", nil, nil, nil, nil])
        #expect(PresentationDeck.isRealSchedule(p))
        p.schedule = nil
        #expect(PresentationDeck.week(p).map { $0?.label } == ["A", "B", nil, nil, nil, nil, nil])
        #expect(!PresentationDeck.isRealSchedule(p))
    }

    @Test func highlightsDropCalibrationTalk() {
        var p = Program(id: 1, aiGenerated: true, generatedAt: "x")
        p.programHighlights = [ProgramHighlight(title: "Calibration first", detail: "x"),
                               ProgramHighlight(title: "Four days", detail: "Fits your week")]
        #expect(PresentationDeck.highlights(p).map(\.title) == ["Four days"])
    }
}

@Suite("Start-day picker (CommitmentScreen.tsx)")
struct StartDayPickerTests {
    let tz = TimeZone(identifier: "Europe/Stockholm")!

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: 15))!
    }

    @Test func quickPicksSkipMondayWhenTomorrow() {
        // Sunday 2026-11-01: tomorrow is Monday, so no separate Monday pick.
        #expect(StartDayPicker.quickPicks(today: date(2026, 11, 1), timeZone: tz).map(\.key) == ["today", "tomorrow"])
        // Monday 2026-11-02: next Monday is a week out.
        let picks = StartDayPicker.quickPicks(today: date(2026, 11, 2), timeZone: tz)
        #expect(picks.map(\.key) == ["today", "tomorrow", "monday"])
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        #expect(c.component(.day, from: picks[2].date) == 9)
    }

    @Test func monthGridIsMondayFirst() {
        // November 2026 starts on a Sunday: six padding cells, 30 days, 42 cells.
        let cells = StartDayPicker.monthCells(date(2026, 11, 15), timeZone: tz)
        #expect(cells.count == 42)
        #expect(cells.prefix(6).allSatisfy { $0 == nil })
        #expect(cells[6] != nil)
        #expect(cells.compactMap { $0 }.count == 30)
    }
}

import Foundation
import Testing
@testable import IntentCore

// Hand-written tests for the Settings and Nutrition page logic (pages/settings.tsx,
// pages/nutrition.tsx), which lives inline in React components.

@Suite("Settings (settings.tsx)")
struct SettingsLogicTests {
    @Test func profilePatchMirrorsTheWebSave() {
        let p = SettingsLogic.profilePatch(name: "Alex", age: "27", weight: "78.4", weightUnit: "kg")
        #expect(p == .init(name: "Alex", weight: 78.4, weightUnit: "kg", age: 27))
        // Blank fields are "not sent", so they can't be cleared (web behaviour).
        let blank = SettingsLogic.profilePatch(name: "", age: "", weight: "", weightUnit: "lbs")
        #expect(blank == .init(name: nil, weight: nil, weightUnit: "lbs", age: nil))
        // Validation reads Number("1e2") = 100, the save reads parseInt = 1 (web bug, kept).
        #expect(SettingsLogic.profileErrors(age: "1e2", weight: "").age == nil)
        #expect(SettingsLogic.profilePatch(name: "", age: "1e2", weight: "", weightUnit: "kg").age == 1)
    }

    @Test func profileErrorsUseTheFieldLimits() {
        let e = SettingsLogic.profileErrors(age: "999", weight: "5")
        #expect(e.age == "Enter an age between 13 and 120.")
        #expect(e.weight == "Enter a weight between 20 and 1,000.")
        #expect(SettingsLogic.profileErrors(age: "27.5", weight: "").age == "Enter your age as a whole number.")
        #expect(SettingsLogic.profileErrors(age: "", weight: "").age == nil)
    }

    @Test func colorLabelsAreProgramFirstThenThisLineagesStoredOnes() {
        let programs = [
            SettingsLogic.ProgramLabels(aiGenerated: true, labels: ["Upper A", "Lower A"]),
            SettingsLogic.ProgramLabels(aiGenerated: true, labels: ["Full Body"]),
            SettingsLogic.ProgramLabels(aiGenerated: false, labels: ["Push", "Pull"]),
        ]
        let ai = SettingsLogic.colorLabels(currentProgramLabels: ["Upper A", "Lower A", nil, ""],
                                           programs: programs, storedLabels: ["Push", "Full Body", "Upper A"],
                                           isIndependent: false)
        #expect(ai.labels == ["Upper A", "Lower A", "Full Body"])
        #expect(ai.order == ["Upper A": 0, "Lower A": 1, "Full Body": 2])
        let manual = SettingsLogic.colorLabels(currentProgramLabels: ["Push", "Pull"], programs: programs,
                                               storedLabels: ["Lower A", "Pull"], isIndependent: true)
        #expect(manual.labels == ["Push", "Pull"])
        let none = SettingsLogic.colorLabels(currentProgramLabels: [], programs: [], storedLabels: ["Lower B"], isIndependent: false)
        #expect(none.labels.isEmpty)
    }

    @Test func hexIsLowercaseSixDigit() {
        #expect(SettingsLogic.hex(r: 1, g: 0.5, b: 0) == "#ff8000")
        #expect(SettingsLogic.hex(r: -1, g: 2, b: 0.231) == "#00ff3b")
        let rgb = DayColors.hexToRgb("#f97316")
        #expect(SettingsLogic.hex(r: rgb.r, g: rgb.g, b: rgb.b) == "#f97316")
    }

    @Test func renewsDateIsEnGBInLocalTime() {
        let stockholm = TimeZone(identifier: "Europe/Stockholm")!
        #expect(SettingsLogic.renewsDate("2026-11-26T23:30:00.000Z", timeZone: stockholm) == "27/11/2026")
        #expect(SettingsLogic.renewsDate("2026-03-05T10:00:00Z", timeZone: stockholm) == "05/03/2026")
        #expect(SettingsLogic.renewsDate("soon", timeZone: stockholm) == nil)
    }
}

@Suite("Nutrition (nutrition.tsx)")
struct NutritionPageTests {
    @Test func targetComesFromTheActiveLineage() {
        #expect(SettingsLogic.nutritionTarget(isIndependent: false, profileTarget: 2600, programTarget: 3100) == 3100)
        #expect(SettingsLogic.nutritionTarget(isIndependent: true, profileTarget: 2600, programTarget: 3100) == 2600)
        #expect(SettingsLogic.nutritionTarget(isIndependent: true, profileTarget: nil, programTarget: 3100) == nil)
    }

    @Test func phaseLineCapitalisesEachWord() {
        #expect(SettingsLogic.phaseLine(shortTermPhase: "bulk", weekInPhase: 3) == "Bulk · Week 3")
        #expect(SettingsLogic.phaseLine(shortTermPhase: "mini_cut", weekInPhase: nil) == "Mini Cut")
        #expect(SettingsLogic.phaseLine(shortTermPhase: "", weekInPhase: 2) == nil)
        #expect(SettingsLogic.phaseLine(shortTermPhase: nil, weekInPhase: 2) == nil)
    }

    @Test func sampleScalesToTheTarget() {
        let plan = NutritionPlan.sample.scaled(toKcal: 3100)
        // Rounded per macro, so within a few kcal of the target.
        #expect(abs(plan.totals.kcal - 3100) < 20)
        #expect(NutritionPlan.sample.scaled(toKcal: nil) == NutritionPlan.sample)
    }
}

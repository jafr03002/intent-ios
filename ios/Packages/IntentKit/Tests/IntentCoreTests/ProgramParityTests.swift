import Foundation
import Testing
@testable import IntentCore

// Parity with trainingTargets, independentTargets, programSchedule, checklistItems,
// calibration, nutritionPlan, greetingLines, phaseColors, dayColors and utils.

@Suite("trainingTargets (parity)")
struct TrainingTargetsParityTests {
    let f: JSON
    init() throws { f = try Fixture.load("trainingTargets") }

    @Test func classifyAndFloor() {
        for c in f["classifyExercise"].array {
            #expect(TrainingTargets.classifyExercise(c["in"].string!).rawValue == c["out"].string, "\(c["in"])")
        }
        for c in f["repRangeFloor"].array {
            #expect(TrainingTargets.repRangeFloor(c["in"].string) == c["out"].int, "\(c["in"])")
        }
    }

    @Test func computeSetTarget() throws {
        for c in f["computeSetTarget"].array {
            let i = c["in"]
            let got = TrainingTargets.computeSetTarget(name: i["name"].string!, lastWeight: i["lastWeight"].double!,
                                                       lastReps: i["lastReps"].int!, targetReps: i["targetReps"].string,
                                                       weightUnit: i["weightUnit"].string!)
            try expectJSON(got, c["out"], "\(i)")
        }
        for c in f["targetFromPreviousSet"].array {
            let i = c["in"]
            let prev: LoggedSet? = i["prev"].isNull ? nil : try i["prev"].decode()
            let got = TrainingTargets.targetFromPreviousSet(prev, name: i["name"].string!, targetReps: i["targetReps"].string,
                                                            weightUnit: i["weightUnit"].string!)
            try expectJSON(got, c["out"], "\(i)")
        }
    }
}

@Suite("independentTargets (parity)")
struct IndependentTargetsParityTests {
    @Test func all() throws {
        let f = try Fixture.load("independentTargets")
        for (opt, js) in zip(IndependentTargets.phaseOptions, f["phaseOptions"].array) {
            #expect(opt.phase.rawValue == js["phase"].string && opt.goal == js["goal"].string && opt.heading == js["heading"].string
                    && opt.tag == js["tag"].string && opt.sub == js["sub"].string)
        }
        #expect(IndependentTargets.phaseOptions.count == f["phaseOptions"].array.count)
        for c in f["goalToPhase"].array {
            #expect(IndependentTargets.goalToPhase(c["in"].string).rawValue == c["out"].string, "\(c["in"])")
        }
        for c in f["phaseGoalWeightError"].array {
            let i = c["in"]
            let got = IndependentTargets.phaseGoalWeightError(phase: IndependentPhase(rawValue: i["phase"].string!)!,
                                                              currentWeight: i["current"].double, goalWeight: i["goal"].string!,
                                                              unit: i["unit"].string!)
            #expect(got == c["out"].string, "\(i)")
        }
        #expect(IndependentTargets.cardioDays == f["cardioDays"].array.map { $0.string! })
        for c in f["orderCardioDays"].array {
            #expect(IndependentTargets.orderCardioDays(c["in"].array.map { $0.string! }) == c["out"].array.map { $0.string! })
        }
    }
}

@Suite("programSchedule (parity)")
struct ProgramScheduleParityTests {
    let f: JSON
    init() throws { f = try Fixture.load("programSchedule") }

    @Test func dates() throws {
        #expect(ProgramScheduleReader.weekdayLabels == f["weekdayLabels"].array.map { $0.string! })
        for c in f["mondayIndexOf"].array {
            let tz = try Fixture.tz(c["tz"])
            #expect(ProgramScheduleReader.mondayIndexOf(c["in"].string!, timeZone: tz) == c["out"].int, "\(c["in"]) in \(c["tz"])")
        }
        for c in f["daysBetween"].array {
            #expect(ProgramScheduleReader.daysBetween(c["in"][0].string!, c["in"][1].string!) == c["out"].int, "\(c["in"])")
        }
        for c in f["todayDateString"].array {
            let tz = try Fixture.tz(c["tz"])
            #expect(ProgramScheduleReader.todayDateString(at: c["in"].date!, timeZone: tz) == c["out"].string, "\(c["in"]) in \(c["tz"])")
        }
    }

    @Test func resolveAndUpcoming() throws {
        for c in f["resolveDayForDate"].array {
            let i = c["in"]
            let schedule: ProgramSchedule? = i["schedule"].isNull ? nil : try i["schedule"].decode()
            #expect(ProgramScheduleReader.resolveDayForDate(schedule, startDate: i["startDate"].string, date: i["date"].string!) == c["out"].int, "\(i)")
        }
        for c in f["upcomingSlots"].array {
            let tz = try Fixture.tz(c["tz"])
            let i = c["in"]
            let schedule: ProgramSchedule? = i["schedule"].isNull ? nil : try i["schedule"].decode()
            let got = ProgramScheduleReader.upcomingSlots(schedule, startDate: i["startDate"].string, from: i["from"].string!,
                                                          count: i["count"].int!, timeZone: tz)
            try expectJSON(got, c["out"], "\(i) in \(c["tz"])")
        }
    }
}

@Suite("checklistItems (parity)")
struct ChecklistItemsParityTests {
    let f: JSON
    init() throws { f = try Fixture.load("checklistItems") }

    func target(_ j: JSON) -> ChecklistTarget {
        ChecklistTarget(targetType: j["targetType"].string.flatMap(TargetType.init(rawValue:)), targetSeconds: j["targetSeconds"].int,
                        targetValue: j["targetValue"].double, targetUnit: j["targetUnit"].string, rounds: j["rounds"].int)
    }

    @Test func data() {
        #expect(ChecklistItems.categories.count == f["categories"].array.count)
        for (meta, js) in zip(ChecklistItems.categories, f["categories"].array) {
            #expect(meta.value.rawValue == js["value"].string && meta.label == js["label"].string && meta.token.css == js["token"].string)
        }
        #expect(ChecklistItems.accent.css == f["accent"].string)
        #expect(ChecklistItems.targetTypeOptions.map(\.value.rawValue) == f["targetTypeOptions"].array.map { $0["value"].string! })
        #expect(ChecklistItems.targetTypeOptions.map(\.label) == f["targetTypeOptions"].array.map { $0["label"].string! })
        #expect(ChecklistItems.distanceUnits == f["distanceUnits"].array.map { $0.string! })
        #expect(ChecklistItems.maxWheelMinutes == f["maxWheel"]["minutes"].int)
        #expect(ChecklistItems.maxWheelSeconds == f["maxWheel"]["seconds"].int)
    }

    @Test func functions() {
        for c in f["parseCategory"].array {
            #expect(ChecklistItems.parseCategory(c["in"].string)?.rawValue == c["out"].string, "\(c["in"])")
        }
        for c in f["formatDuration"].array {
            #expect(ChecklistItems.formatDuration(c["in"].double!) == c["out"].string, "\(c["in"])")
        }
        for c in f["describeTarget"].array {
            #expect(ChecklistItems.describeTarget(target(c["in"])) == c["out"].string, "\(c["in"])")
        }
        for c in f["describeTargetWithRounds"].array {
            #expect(ChecklistItems.describeTargetWithRounds(target(c["in"])) == c["out"].string, "\(c["in"])")
        }
        for c in f["clampTargetValue"].array {
            let got = ChecklistItems.clampTargetValue(c["in"][0].double!, targetType: TargetType(rawValue: c["in"][1].string!)!)
            #expect(got == c["out"].double, "\(c["in"])")
        }
    }
}

@Suite("calibration (parity)")
struct CalibrationParityTests {
    let f: JSON
    init() throws { f = try Fixture.load("calibration") }

    func rangeJSON(_ phase: String?, _ start: Date, _ end: Date) -> JSON {
        var o: [String: JSON] = ["start": .number(ms(start)!), "end": .number(ms(end)!)]
        if let phase { o["phase"] = .string(phase) }
        return .object(o)
    }

    @Test func scenarios() throws {
        var byName: [String: JSON] = [:]
        for s in f["scenarios"].array { byName[s["name"].string!] = s }
        for r in f["results"].array {
            let tz = try Fixture.tz(r["tz"])
            let s = try #require(byName[r["scenario"].string!])
            let programs: [PhaseRow] = try s["programs"].decode()
            let onboarding = s["onboardingCompletedAt"].string
            let today = r["today"].date!
            let ctx = "\(r["scenario"]) @ \(r["today"]) in \(r["tz"])"

            #expect(ms(Calibration.trainingStart(programs, onboardingCompletedAt: onboarding, timeZone: tz)) == r["trainingStart"].double, "trainingStart: \(ctx)")

            let ranges = Calibration.buildPhaseRanges(programs, onboardingCompletedAt: onboarding, today: today, timeZone: tz)
            #expect(JSON.array(ranges.map { rangeJSON($0.phase, $0.start, $0.end) }) == r["ranges"], "ranges: \(ctx)")

            let groups = Calibration.buildCalibrationGroups(ranges, timeZone: tz)
            #expect(JSON.array(groups.map { rangeJSON(nil, $0.start, $0.end) }) == r["groups"], "groups: \(ctx)")

            for p in r["probes"].array {
                let at = p["at"].date!
                #expect(Calibration.findPhaseRange(ranges, at)?.phase == p["phase"].string, "phase at \(p["at"]): \(ctx)")
                let g = Calibration.findCalibrationGroup(groups, at)
                #expect((g.map { rangeJSON(nil, $0.start, $0.end) } ?? .null) == p["group"], "group at \(p["at"]): \(ctx)")
                #expect(g.map { Calibration.isReviewPossible($0, at, timeZone: tz) } == p["reviewPossible"].bool, "review at \(p["at"]): \(ctx)")
            }

            let gate = Calibration.checkinGate(programs, latestCheckinAt: s["latestCheckinAt"].string, now: today, timeZone: tz)
            let g = r["gate"]
            switch gate {
            case .open(let first):
                #expect(g["open"].bool == true && g["firstAfterReview"].bool == first, "gate: \(ctx) -> \(g)")
            case .closedForCalibration:
                #expect(g["open"].bool == false && g["reason"].string == "calibration", "gate: \(ctx) -> \(g)")
            case .closedUntil(let opensAt):
                #expect(g["open"].bool == false && g["reason"].string == "after_review", "gate: \(ctx) -> \(g)")
                let o = opensAt.timeIntervalSince1970
                #expect(o.isNaN ? g["opensAt"].isNull : ms(opensAt) == g["opensAt"].double, "opensAt: \(ctx)")
            }

            let seenValues: [String?] = [nil, "2026-10-01T00:00:00Z"]
            for (seen, want) in zip(seenValues, r["walkthrough"].array) {
                let got = Calibration.shouldShowCalibrationWalkthrough(programs, onboardingCompletedAt: onboarding,
                                                                      calibrationWalkthroughSeenAt: seen, today: today, now: today, timeZone: tz)
                #expect(got == want.bool, "walkthrough(seen: \(seen ?? "nil")): \(ctx)")
            }
            let other = r["walkthroughAtOtherNow"]
            let gotOther = Calibration.shouldShowCalibrationWalkthrough(programs, onboardingCompletedAt: onboarding,
                                                                       calibrationWalkthroughSeenAt: nil, today: today,
                                                                       now: other["now"].date!, timeZone: tz)
            #expect(gotOther == other["out"].bool, "walkthrough at another now: \(ctx)")

            for (p, want) in zip(programs, r["locked"].array) {
                #expect(Calibration.isPreCalibrationLocked(aiGenerated: p.aiGenerated, startDate: p.startDate, today: today, timeZone: tz) == want.bool, "locked: \(ctx)")
            }
        }
    }

    @Test func helpers() throws {
        for c in f["addDays"].array {
            let tz = try Fixture.tz(c["tz"])
            #expect(ms(Calibration.addDays(c["in"][0].date!, c["in"][1].int!, timeZone: tz)) == c["out"].double, "\(c["in"]) in \(c["tz"])")
        }
        for c in f["localDateString"].array {
            let tz = try Fixture.tz(c["tz"])
            #expect(Calibration.localDateString(c["in"].date!, timeZone: tz) == c["out"].string, "\(c["in"]) in \(c["tz"])")
        }
        for c in f["parseLocalDateString"].array {
            let tz = try Fixture.tz(c["tz"])
            #expect(ms(Calibration.parseLocalDateString(c["in"].string!, timeZone: tz)) == c["out"].double, "\(c["in"]) in \(c["tz"])")
        }
        for c in f["isCalibrationProgram"].array {
            let i = c["in"]
            #expect(Calibration.isCalibrationProgram(aiGenerated: i["aiGenerated"].bool, shortTermPhase: i["shortTermPhase"].string) == c["out"].bool, "\(i)")
        }
        for c in f["calibrationBriefingHref"].array {
            #expect(Calibration.calibrationBriefingHref(dayNumber: c["in"].int!) == c["out"].string)
        }
        for c in f["isPreCalibrationLocked"].array {
            let tz = try Fixture.tz(c["tz"])
            let p = c["in"]["program"]
            let got = Calibration.isPreCalibrationLocked(aiGenerated: p["aiGenerated"].bool, startDate: p["startDate"].string,
                                                         today: c["in"]["today"].date!, timeZone: tz)
            #expect(got == c["out"].bool, "\(c["in"]) in \(c["tz"])")
        }
        #expect(Calibration.firstCheckinAfterReviewDays == f["firstCheckinAfterReviewDays"].int)
    }
}

@Suite("nutritionPlan + greetingLines (parity)")
struct DashboardParityTests {
    @Test func nutrition() throws {
        let f = try Fixture.load("nutritionPlan")
        try expectJSON(NutritionPlan.sample, f["samplePlan"])
        try expectJSON(NutritionPlan.sample.totals, f["planTotals"])
        for c in f["kcalOf"].array {
            #expect(NutritionPlan.kcalOf(try c["in"].decode()) == c["out"].double, "\(c["in"])")
        }
        for c in f["scalePlan"].array {
            try expectJSON(NutritionPlan.sample.scaled(toKcal: c["in"].double), c["out"], "scale to \(c["in"])")
        }
        for c in f["formatAmount"].array {
            #expect(NutritionPlan.formatAmount(try c["in"].decode()) == c["out"].string, "\(c["in"])")
        }
    }

    struct Day: NamedDay, Decodable, Equatable { let dayNumber: Int; let label: String }

    @Test func greetings() throws {
        let f = try Fixture.load("greetingLines")
        for c in f["greetingLine"].array {
            let tz = try Fixture.tz(c["tz"])
            let got = GreetingLines.greetingLine(dayLabel: c["in"]["label"].string, at: c["in"]["at"].date!, timeZone: tz)
            #expect(got == c["out"].string, "\(c["in"]) in \(c["tz"])")
        }
        for c in f["nextSessionDay"].array {
            let days: [Day] = try c["in"]["days"].decode()
            let got = GreetingLines.nextSessionDay(days, lastCompletedDayNumber: c["in"]["last"].int)
            #expect(got?.dayNumber == c["out"]["dayNumber"].int && got?.label == c["out"]["label"].string, "\(c["in"])")
        }
    }
}

@Suite("phaseColors + dayColors + utils (parity)")
struct ColorsParityTests {
    @Test func phases() throws {
        let f = try Fixture.load("colors")
        for (key, hue) in f["phaseHues"].object {
            let c = try #require(PhaseColors.hue(key), "missing hue \(key)")
            #expect(c.h == hue["h"].double && c.s == hue["s"].double && c.l == hue["l"].double, "\(key)")
        }
        #expect(PhaseColors.hues.count == f["phaseHues"].object.count)
        for c in f["phases"].array {
            let p = c["in"].string!
            #expect(PhaseColors.solid(p) == c["solid"].string && PhaseColors.soft(p) == c["soft"].string && PhaseColors.label(p) == c["label"].string, "\(p)")
        }
    }

    @Test func days() throws {
        let f = try Fixture.load("colors")
        #expect(DayColors.palette == f["dayPalette"].array.map { $0.string! })
        for c in f["dayTones"].array {
            let t = DayColors.dayTones(c["in"].string!)
            let o = c["out"]
            #expect(t.solid == o["solid"].string && t.soft == o["soft"].string && t.text == o["text"].string, "\(c["in"])")
            #expect(t.on == o["on"].string && t.glow == o["glow"].string && t.parts == o["parts"].string, "\(c["in"])")
        }
        for c in f["buildDayColorOrder"].array {
            let got = DayColors.buildDayColorOrder(programLabels: c["in"]["program"].array.map(\.string),
                                                   extraLabels: c["in"]["extra"].array.map(\.string))
            try expectJSON(got, c["out"], "\(c["in"])")
        }
        for c in f["dayColorHex"].array {
            let i = c["in"]
            let order = i["order"].object.mapValues { $0.int! }
            let custom = i["custom"].object.mapValues { $0.string! }
            #expect(DayColors.dayColorHex(i["label"].string!, order: order, custom: custom) == c["out"].string, "\(i)")
        }
        for c in f["dayColorAt"].array {
            #expect(DayColors.dayColorAt(c["in"].int!) == c["out"].string)
        }
    }

    @Test func splitType() throws {
        for c in try Fixture.load("utils")["formatSplitType"].array {
            #expect(SplitType.format(c["in"].string!) == c["out"].string, "\(c["in"])")
        }
    }
}

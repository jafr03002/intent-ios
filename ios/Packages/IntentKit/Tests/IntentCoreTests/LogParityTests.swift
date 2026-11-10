import Foundation
import Testing
@testable import IntentCore

// Parity with the TS behind the /log screen: workoutSession, sessionLogs, nextSet,
// sessionDuration, fieldLimits, usePrDetection, useSessionTimers.

final class Clock: @unchecked Sendable {
    var now: Double
    init(_ now: Double) { self.now = now }
}

private struct Resolved: Encodable {
    let pointer: ActiveSessionPointer
    let draft: WorkoutDraft
}

@Suite("workoutSession (parity)")
struct WorkoutSessionParityTests {
    let f: JSON
    init() throws { f = try Fixture.load("workoutSession") }

    @Test func keys() {
        for c in f["draftKey"].array {
            let a = c["in"].array
            #expect(WorkoutSession.draftKey(userId: a[0].string!, programId: a[1].int!, dayNumber: a[2].int!) == c["out"].string)
        }
        for c in f["activeSessionKey"].array {
            #expect(WorkoutSession.activeSessionKey(userId: c["in"].string!) == c["out"].string)
        }
        #expect(WorkoutSession.draftMaxAgeMs == f["draftMaxAgeMs"].double)
    }

    @Test func storageScenarios() throws {
        for scenario in f["scenarios"].array {
            let clock = Clock(0)
            let store = InMemoryKeyValueStore()
            var announcements = 0
            let sessions = WorkoutSessionStore(store: store, now: { clock.now }, onActiveSessionChange: { announcements += 1 })
            for step in scenario["steps"].array {
                clock.now = step["now"].double!
                let args = step["args"].array
                let op = step["op"].string!
                var result = JSON.null
                switch op {
                case "refuse":
                    store.refusesWrites = true
                case "startSession":
                    result = .bool(sessions.startSession(userId: args[0].string!, programId: args[1].int!, dayNumber: args[2].int!))
                case "resolveActiveSession":
                    if let r = sessions.resolveActiveSession(userId: args[0].string!) {
                        result = try Fixture.json(Resolved(pointer: r.pointer, draft: r.draft))
                    }
                case "loadActiveSession":
                    if let p = sessions.loadActiveSession(userId: args[0].string!) { result = try Fixture.json(p) }
                case "loadDraft":
                    if let d = sessions.loadDraft(key: args[0].string!) { result = try Fixture.json(d) }
                case "saveDraft":
                    sessions.saveDraft(key: args[0].string!, logs: try args[1].decode([DraftExercise].self), startedAt: args[2].double)
                case "saveActiveSession":
                    sessions.saveActiveSession(userId: args[0].string!, pointer: try args[1].decode(ActiveSessionPointer.self))
                case "discardActiveSession":
                    sessions.discardActiveSession(userId: args[0].string!)
                case "clearDraft":
                    sessions.clearDraft(key: args[0].string!)
                default:
                    Issue.record("unknown op \(op)")
                }
                let ctx = "\(scenario["name"]) / \(op) @ \(step["now"])"
                try expectJSON(result, step["result"], "result: \(ctx)")
                var dump: [String: JSON] = [:]
                for (k, v) in store.allValues { dump[k] = try Fixture.decoder.decode(JSON.self, from: Data(v.utf8)) }
                try expectJSON(dump, step["storage"], "storage: \(ctx)")
            }
            #expect(announcements > 0)
        }
    }
}

@Suite("sessionLogs (parity)")
struct SessionLogsParityTests {
    let f: JSON
    init() throws { f = try Fixture.load("sessionLogs") }

    @Test func isEmptySet() throws {
        for c in f["isEmptySet"].array {
            let s: LoggedSet? = c["in"].isNull ? nil : try c["in"].decode()
            #expect(SessionLogs.isEmptySet(s) == c["out"].bool, "\(c["in"])")
        }
    }

    @Test func formatShortDate() throws {
        for c in f["formatShortDate"].array {
            let tz = try Fixture.tz(c["tz"])
            #expect(SessionLogs.formatShortDate(c["in"].string, timeZone: tz) == c["out"].string, "\(c["in"]) in \(c["tz"])")
        }
    }

    @Test func dayStructureKey() throws {
        for c in f["dayStructureKey"].array {
            let day: ProgramDay? = c["in"].isNull ? nil : try c["in"].decode()
            #expect(SessionLogs.dayStructureKey(day) == c["out"].string)
        }
    }

    @Test func buildAndReconcile() throws {
        for c in f["buildFreshLogs"].array {
            try expectJSON(SessionLogs.buildFreshLogs(try c["in"].decode()), c["out"], "buildFreshLogs")
        }
        for c in f["reconcileDraftLogs"].array {
            let out = SessionLogs.reconcileDraftLogs(try c["draft"].decode(), day: try c["day"].decode(), now: c["now"].double!)
            try expectJSON(out, c["out"], "reconcile: \(c["name"])")
        }
    }

    @Test func estimatedOneRepMaxAndPrevSet() throws {
        for c in f["estimatedOneRepMax"].array {
            let a = c["in"].array
            #expect(SessionLogs.estimatedOneRepMax(weight: a[0].double!, reps: a[1].double!) == c["out"].double)
        }
        for c in f["formatPrevSet"].array {
            let i = c["in"]
            let s: LoggedSet? = i["set"].isNull ? nil : try i["set"].decode()
            let got = SessionLogs.formatPrevSet(s, weightUnit: i["unit"].string!, isUnilateral: i["isUnilateral"].bool!)
            #expect(got == c["out"].string, "\(i)")
        }
    }

    @Test func lastSessionLookup() throws {
        for c in f["buildLastSessionLookup"].array {
            let history: [WorkoutLog] = try c["in"].decode()
            let got = SessionLogs.buildLastSessionLookup(history)
            try expectJSON(got.lastSetsByExercise, c["out"]["lastSetsByExercise"])
            try expectJSON(got.lastNoteByExercise, c["out"]["lastNoteByExercise"])
        }
    }
}

@Suite("nextSet + sessionDuration + fieldLimits (parity)")
struct LoggerHelpersParityTests {
    @Test func nextSet() throws {
        for c in try Fixture.load("nextSet")["cases"].array {
            let logs: [DraftExercise] = try c["in"].decode()
            try expectJSON(NextSet.findNextUnloggedSet(logs), c["next"])
            #expect(NextSet.hasAnyLoggedSet(logs) == c["any"].bool)
        }
    }

    @Test func sessionDuration() throws {
        let f = try Fixture.load("sessionDuration")
        let k = f["constants"]
        #expect(SessionDuration.minSessionSeconds == k["MIN_SESSION_SECONDS"].int)
        #expect(SessionDuration.maxSessionSeconds == k["MAX_SESSION_SECONDS"].int)
        #expect(SessionDuration.minSecondsPerSet == k["MIN_SECONDS_PER_SET"].int)
        #expect(SessionDuration.maxSecondsPerSet == k["MAX_SECONDS_PER_SET"].int)
        #expect(SessionDuration.minSessionsForAverage == k["MIN_SESSIONS_FOR_AVERAGE"].int)
        for c in f["plausibleBand"].array {
            try expectJSON(SessionDuration.plausibleBand(setCount: c["in"].int!), c["out"], "band \(c["in"])")
        }
        for c in f["countsTowardAverage"].array {
            let got = SessionDuration.countsTowardAverage(durationSeconds: c["in"]["durationSeconds"].int,
                                                          exercisesLogged: try c["in"]["exercisesLogged"].decode())
            #expect(got == c["out"].bool, "\(c["in"])")
        }
        for c in f["formatClock"].array {
            #expect(SessionDuration.formatClock(c["in"].double!) == c["out"].string, "clock \(c["in"])")
        }
        for c in f["formatSessionLength"].array {
            #expect(SessionDuration.formatSessionLength(c["in"].double!) == c["out"].string, "length \(c["in"])")
        }
        for c in f["formatStartTime"].array {
            let tz = try Fixture.tz(c["tz"])
            #expect(SessionDuration.formatStartTime(c["in"].string!, timeZone: tz) == c["out"].string, "\(c["in"]) in \(c["tz"])")
        }
    }

    @Test func fieldLimits() throws {
        let f = try Fixture.load("fieldLimits")
        for (key, limit) in f["limits"].object {
            let swift = try #require(FieldLimits.all[key], "missing limit \(key)")
            #expect(swift.min == limit["min"].double && swift.max == limit["max"].double, "\(key)")
            #expect(swift.noun == limit["noun"].string && swift.article.rawValue == limit["article"].string, "\(key)")
            #expect(swift.unit == limit["unit"].string && swift.integer == (limit["integer"].bool ?? false), "\(key)")
        }
        #expect(FieldLimits.all.count == f["limits"].object.count)
        #expect(FieldLimits.loggedSetWeight.max == f["loggedSetBounds"]["weight"]["max"].double)
        #expect(FieldLimits.loggedSetReps.max == f["loggedSetBounds"]["reps"]["max"].double)
        #expect(FieldLimits.maxExerciseName == f["maxLengths"]["MAX_EXERCISE_NAME"].int)
        #expect(FieldLimits.maxDayLabel == f["maxLengths"]["MAX_DAY_LABEL"].int)
        #expect(FieldLimits.maxProfileName == f["maxLengths"]["MAX_PROFILE_NAME"].int)
        for c in f["rangeError"].array {
            let limit = FieldLimits.all[c["key"].string!]!
            #expect(FieldLimits.rangeError(c["raw"].string!, limit) == c["out"].string, "\(c["key"]): \(c["raw"])")
        }
        for c in f["clampToBounds"].array {
            let a = c["in"].array
            #expect(FieldLimits.clampToBounds(a[0].double!, Bounds(min: a[1].double!, max: a[2].double!)) == c["out"].double, "\(c["in"])")
        }
        for c in f["allInRange"].array {
            let pairs = c["in"].array.map { p in (p[0].string!, FieldLimits.all[p[1].string!]!) }
            #expect(FieldLimits.allInRange(pairs) == c["out"].bool)
        }
    }
}

@Suite("usePrDetection + useSessionTimers (parity)")
struct HookParityTests {
    @Test func prDetection() throws {
        for s in try Fixture.load("prDetection")["scenarios"].array {
            var detector = PrDetector(history: try s["history"].decode(), personalRecords: try s["personalRecords"].decode())
            for c in s["calls"].array {
                let i = c["in"]
                let got = detector.judgeSet(name: i["name"].string!, isUnilateral: i["isUnilateral"].bool!,
                                            set: try i["set"].decode(), wasPr: i["wasPr"].bool!)
                #expect(got.isNewPr == c["out"].bool, "\(s["name"]): \(i)")
            }
        }
    }

    @Test func sessionTimers() throws {
        for c in try Fixture.load("sessionTimers")["cases"].array {
            let logs: [DraftExercise] = try c["logs"].decode()
            let now = c["now"].double!
            // The hook's expiry effect runs on mount; an action then patches the result.
            var out = SessionTimers.completeExpiredTimers(logs, now: now) ?? logs
            if !c["action"].isNull {
                let name = c["action"][0].string!, idx = c["action"][1].int!
                switch name {
                case "startTimer": out = SessionTimers.startTimer(out, exIdx: idx, now: now)
                case "pauseTimer": out = SessionTimers.pauseTimer(out, exIdx: idx, now: now)
                case "resetTimer": out = SessionTimers.resetTimer(out, exIdx: idx)
                default: Issue.record("unknown action \(name)")
                }
            }
            try expectJSON(out, c["out"], "\(c["name"])")
        }
    }
}

@Suite("muscles + exerciseLibrary (parity)")
struct ExerciseLibraryParityTests {
    let f: JSON
    init() throws { f = try Fixture.load("exerciseLibrary") }

    @Test func data() throws {
        #expect(Muscle.allCases.map(\.label) == f["muscleOptions"].array.map { $0.string! })
        for m in Muscle.allCases {
            #expect(m.color.css == f["muscleColors"][m.label].string, "\(m)")
            #expect(ExerciseLibrary.byMuscle[m] ?? [] == f["library"][m.label].array.map { $0.string! }, "\(m)")
        }
        try expectJSON(ExerciseLibrary.allExercises, f["all"])
        #expect(ExerciseLibrary.groups.map(\.muscle.label) == f["groups"].array.map { $0["muscle"].string! })
    }

    @Test func search() throws {
        for c in f["search"].array {
            let q = c["query"].string!
            let got = c["limit"].isNull ? ExerciseLibrary.search(q) : ExerciseLibrary.search(q, limit: c["limit"].int!)
            try expectJSON(got, c["out"], "search(\(q))")
        }
    }
}

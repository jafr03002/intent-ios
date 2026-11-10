import Foundation

// The pure state transitions of pages/log.tsx and components/workout/SetRow.tsx:
// typing into a set, ticking checklist rounds, notes, and building the POST
// /workouts body. Every function returns new logs; the view model holds state.

public enum SetField: String, Sendable, CaseIterable, Codable {
    case weight, reps, repsLeft, repsRight
}

public enum SetEditing {
    /// The weight box: `parseFloat(text) || 0`.
    public static func parseWeightInput(_ text: String) -> Double {
        let v = JS.parseFloat(text)
        return v.isNaN || v == 0 ? 0 : v
    }

    /// A reps box: `parseInt(text) || 0`.
    public static func parseRepsInput(_ text: String) -> Double {
        let v = JS.parseInt(text)
        return v.isNaN || v == 0 ? 0 : v
    }

    /// Sets are saved implicitly by typing. The value is clamped to the API's bands;
    /// weight and reps together (both sides for a unilateral lift) mark the set
    /// completed, and a completed set is judged for a PR inline.
    ///
    /// Returns the new logs plus the PR judgement (nil when the set isn't complete),
    /// whose `shouldFlash` is the toast trigger.
    public static func updateSet(_ logs: [DraftExercise], exIdx: Int, setIdx: Int, field: SetField, value: Double,
                                 prDetector: inout PrDetector) -> (logs: [DraftExercise], pr: PrJudgement?) {
        guard logs.indices.contains(exIdx), logs[exIdx].sets.indices.contains(setIdx) else { return (logs, nil) }
        let ex = logs[exIdx]
        let set = ex.sets[setIdx]
        let bounded = FieldLimits.clampToBounds(value, field == .weight ? FieldLimits.loggedSetWeight : FieldLimits.loggedSetReps)
        var merged = set
        switch field {
        case .weight: merged.weight = bounded
        case .reps: merged.reps = Int(bounded.rounded(.towardZero))
        case .repsLeft: merged.repsLeft = Int(bounded.rounded(.towardZero))
        case .repsRight: merged.repsRight = Int(bounded.rounded(.towardZero))
        }
        let hasReps = ex.isUnilateral ? merged.repsLeft > 0 && merged.repsRight > 0 : merged.reps > 0
        let completed = merged.weight > 0 && hasReps
        var judgement: PrJudgement?
        if completed {
            judgement = prDetector.judgeSet(name: ex.name, isUnilateral: ex.isUnilateral, set: SetNumbers(merged), wasPr: set.isNewPr)
        }
        merged.completed = completed
        merged.isNewPr = judgement?.isNewPr ?? false
        var out = logs
        out[exIdx].sets[setIdx] = merged
        return (out, judgement)
    }

    /// A calibration set has no numbers: the tick IS the completion.
    public static func toggleSetDone(_ logs: [DraftExercise], exIdx: Int, setIdx: Int) -> [DraftExercise] {
        guard logs.indices.contains(exIdx), logs[exIdx].sets.indices.contains(setIdx) else { return logs }
        var out = logs
        out[exIdx].sets[setIdx].completed.toggle()
        return out
    }

    /// Completes the current round of a timed item (one-way: never un-ticks).
    public static func completeChecklistRound(_ logs: [DraftExercise], exIdx: Int) -> [DraftExercise] {
        guard logs.indices.contains(exIdx) else { return logs }
        var out = logs
        out[exIdx].completedRounds = min(out[exIdx].targetRounds, out[exIdx].completedRounds + 1)
        out[exIdx].timerEndsAt = nil
        out[exIdx].timerPausedRemaining = nil
        return out
    }

    /// Tick the next round, or untick everything once all rounds are done. Ticking by
    /// hand cancels any running countdown.
    public static func toggleChecklistRound(_ logs: [DraftExercise], exIdx: Int) -> [DraftExercise] {
        guard logs.indices.contains(exIdx) else { return logs }
        var out = logs
        let done = out[exIdx].completedRounds >= out[exIdx].targetRounds
        out[exIdx].completedRounds = done ? 0 : out[exIdx].completedRounds + 1
        out[exIdx].timerEndsAt = nil
        out[exIdx].timerPausedRemaining = nil
        return out
    }

    public static func updateNotes(_ logs: [DraftExercise], exIdx: Int, notes: String) -> [DraftExercise] {
        guard logs.indices.contains(exIdx) else { return logs }
        var out = logs
        out[exIdx].notes = notes
        return out
    }

    public static func toggleNotes(_ logs: [DraftExercise], exIdx: Int) -> [DraftExercise] {
        guard logs.indices.contains(exIdx) else { return logs }
        var out = logs
        out[exIdx].showNotes.toggle()
        return out
    }

    /// The POST /workouts body for a finished session, exactly as log.tsx builds it.
    ///
    /// NOTE (ported faithfully from the web): `date` is the **UTC** calendar date of
    /// `now` (`new Date().toISOString().split("T")[0]`), not the user's local date,
    /// so a session finished shortly after local midnight east of UTC (or in the
    /// evening west of it) is filed under a different day than the user sees.
    public static func buildWorkoutLogInput(logs: [DraftExercise], activeDay: ProgramDay?, programWeekNumber: Int?,
                                            startedAt: Double?, now: Double, isCalibration: Bool,
                                            note: String?) -> WorkoutLogInput {
        let exercises: [LoggedExercise] = logs.filter { !JS.trim($0.name).isEmpty }.map { ex in
            let notes: String? = ex.notes.isEmpty ? nil : ex.notes
            if ex.kind == .checklist {
                return LoggedExercise(name: ex.name, muscle: "", sets: [], notes: notes, kind: .checklist,
                                      completedRounds: ex.completedRounds, targetSeconds: ex.targetSeconds,
                                      category: ex.category)
            }
            let sets: [LoggedSet] = ex.sets.map { s in
                if isCalibration {
                    return LoggedSet(setNumber: s.setNumber, weight: 0, reps: nil, completed: s.completed, isNewPr: false)
                }
                if ex.isUnilateral {
                    return LoggedSet(setNumber: s.setNumber, weight: s.weight, reps: nil, repsLeft: s.repsLeft,
                                     repsRight: s.repsRight, completed: s.completed, isNewPr: s.isNewPr)
                }
                return LoggedSet(setNumber: s.setNumber, weight: s.weight, reps: s.reps, completed: s.completed, isNewPr: s.isNewPr)
            }
            return LoggedExercise(name: ex.name, muscle: ex.muscle, sets: sets, notes: notes, kind: .lift)
        }
        let started = startedAt.flatMap { $0 == 0 ? nil : $0 }
        return WorkoutLogInput(
            date: String(JSDate.isoString(now).prefix(10)),
            dayNumber: activeDay?.dayNumber ?? 1,
            weekNumber: programWeekNumber ?? 1,
            dayLabel: activeDay?.label,
            exercisesLogged: exercises,
            notes: note,
            loggingMode: isCalibration ? .calibration : .full,
            startedAt: started.map(JSDate.isoString),
            durationSeconds: started.map { Int(JS.round((now - $0) / 1000)) }
        )
    }
}

extension JSDate {
    /// `date.toISOString()`: "2026-08-12T10:00:00.000Z".
    static func isoString(_ t: Double) -> String {
        guard let p = utcParts(t) else { return "Invalid Date" }
        func pad(_ n: Int, _ w: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: Swift.max(0, w - s.count)) + s
        }
        let year = p.year >= 0 && p.year <= 9999 ? pad(p.year, 4) : (p.year < 0 ? "-" : "+") + pad(Swift.abs(p.year), 6)
        return "\(year)-\(pad(p.month0 + 1, 2))-\(pad(p.day, 2))T\(pad(p.hour, 2)):\(pad(p.minute, 2)):\(pad(p.second, 2)).\(pad(p.ms, 3))Z"
    }
}

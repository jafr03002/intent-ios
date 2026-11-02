import Foundation

// Port of lib/sessionLogs.ts: the pure half of the workout logger - building a
// session's rows from a program day, folding a saved draft back into them, and
// reading the "last time" hints out of saved history.

public struct LastNote: Sendable, Equatable, Codable {
    public var text: String
    public var date: String?
    public init(text: String, date: String?) { self.text = text; self.date = date }
}

public struct LastSessionLookup: Sendable, Equatable {
    /// Keyed by lowercased exercise name: the full set list of the newest prior log
    /// that has real data for it.
    public var lastSetsByExercise: [String: [LoggedSet]]
    /// That same session's note for the exercise, when it had one.
    public var lastNoteByExercise: [String: LastNote]
}

public enum SessionLogs {
    /// A set with no real data (weight and every rep field zero/empty).
    public static func isEmptySet(_ s: LoggedSet?) -> Bool {
        guard let s else { return true }
        return s.weight == 0 && (s.reps ?? 0) == 0 && (s.repsLeft ?? 0) == 0 && (s.repsRight ?? 0) == 0
    }

    /// "12 Aug" (en-GB, day + short month, in `timeZone`) - nil for a missing or
    /// unreadable date. Note en-GB's September is "Sept".
    public static func formatShortDate(_ date: String?, timeZone: TimeZone = .current) -> String? {
        guard let date, !date.isEmpty else { return nil }
        let t = JSDate.parse(date, timeZone)
        guard let p = JSDate.localParts(t, timeZone) else { return nil }
        return "\(p.day) \(enGBShortMonths[p.month0])"
    }

    static let enGBShortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept", "Oct", "Nov", "Dec"]

    /// Identifies the shape of a day's exercise list, so an edit to the program can be
    /// told apart from a plain refetch. Ignores muscle, cue and category on purpose.
    public static func dayStructureKey(_ day: ProgramDay?) -> String {
        (day?.exercises ?? []).map { ex in
            let seconds = ex.targetSeconds.map(String.init) ?? ""
            return "\(ex.kind.rawValue):\(ex.name):\(ex.sets):\(ex.reps):\(seconds)"
        }.joined(separator: "|")
    }

    /// Rebuilds the session from the CURRENT program day, then folds the user's work
    /// back in by (case-insensitive) exercise name. Structure comes from the program,
    /// only data from the draft. `now` (epoch ms) drops countdowns that expired while
    /// the app was closed.
    public static func reconcileDraftLogs(_ draftLogs: [DraftExercise], day: ProgramDay, now: Double) -> [DraftExercise] {
        var byName: [String: DraftExercise] = [:]
        for entry in draftLogs where !entry.name.isEmpty {
            byName[JS.lower(entry.name)] = entry
        }
        return buildFreshLogs(day).map { fresh in
            guard let saved = byName[JS.lower(fresh.name)] else { return fresh }
            var out = fresh
            out.notes = saved.notes
            out.showNotes = saved.showNotes
            if fresh.kind == .checklist {
                // Clamp: the program's round count may have been lowered since.
                out.completedRounds = min(fresh.targetRounds, saved.completedRounds)
                if let ends = saved.timerEndsAt, ends > now { out.timerEndsAt = ends } else { out.timerEndsAt = nil }
                out.timerPausedRemaining = saved.timerPausedRemaining
                return out
            }
            // The program decides how many sets are prescribed; copy across what was logged.
            out.sets = fresh.sets.enumerated().map { i, s in
                guard i < saved.sets.count else { return s }
                var merged = saved.sets[i]
                merged.setNumber = s.setNumber
                return merged
            }
            return out
        }
    }

    public static func buildFreshLogs(_ day: ProgramDay) -> [DraftExercise] {
        day.exercises.map { ex in
            let isChecklist = ex.kind == .checklist
            return DraftExercise(
                name: ex.name,
                muscle: ex.muscle,
                isUnilateral: ex.isUnilateral ?? false,
                // Deliberately empty for a checklist item: a placeholder set would be
                // picked up by the volume and PR maths.
                sets: isChecklist ? [] : (0..<max(0, ex.sets)).map { DraftSet(setNumber: $0 + 1) },
                targetSets: ex.sets,
                targetReps: ex.reps,
                kind: isChecklist ? .checklist : .lift,
                targetType: ex.targetType,
                targetSeconds: ex.targetSeconds,
                targetValue: ex.targetValue,
                targetUnit: ex.targetUnit,
                category: ChecklistItems.parseCategory(ex.category),
                completedRounds: 0,
                targetRounds: max(1, ex.sets)
            )
        }
    }

    /// Estimated one-rep max (Epley). PRs are judged on this, not raw weight.
    public static func estimatedOneRepMax(weight: Double, reps: Double) -> Double {
        weight * (1 + reps / 30)
    }

    /// One previous set for the per-set "last time" hint: "80 kg × 8",
    /// "20 kg × 10L / 9R", or "80 kg × 8 (both sides)" when the exercise is now
    /// unilateral but the set was logged bilaterally. Nil for an empty set.
    public static func formatPrevSet(_ s: LoggedSet?, weightUnit: String, isUnilateral: Bool) -> String? {
        guard let s, !isEmptySet(s) else { return nil }
        if s.repsLeft != nil || s.repsRight != nil {
            return "\(JS.string(s.weight)) \(weightUnit) × \(s.repsLeft ?? 0)L / \(s.repsRight ?? 0)R"
        }
        let base = "\(JS.string(s.weight)) \(weightUnit) × \(s.reps ?? 0)"
        return isUnilateral ? "\(base) (both sides)" : base
    }

    /// "Last time" lookup from newest-first history: per exercise, the first log that
    /// has real data for it, plus that session's note and date.
    public static func buildLastSessionLookup(_ history: [WorkoutLog]?) -> LastSessionLookup {
        var sets: [String: [LoggedSet]] = [:]
        var notes: [String: LastNote] = [:]
        for log in history ?? [] {
            for ex in log.exercisesLogged {
                let key = JS.lower(ex.name)
                if key.isEmpty || sets[key] != nil { continue }
                if ex.sets.contains(where: { !isEmptySet($0) }) {
                    sets[key] = ex.sets
                    let text = JS.trim(ex.notes ?? "")
                    if !text.isEmpty { notes[key] = LastNote(text: text, date: log.date) }
                }
            }
        }
        return LastSessionLookup(lastSetsByExercise: sets, lastNoteByExercise: notes)
    }
}

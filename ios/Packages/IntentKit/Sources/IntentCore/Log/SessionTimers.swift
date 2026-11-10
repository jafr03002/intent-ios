import Foundation

// The pure core of hooks/useSessionTimers.ts and the countdown maths in
// components/workout/ChecklistItemCard.tsx.
//
// Both clocks are DERIVED from absolute wall-clock timestamps (`startedAt`,
// `timerEndsAt`, epoch ms) at every tick rather than counted, so a suspended app
// resumes showing the right value. The view layer owns the tick (a 1 s timer for
// the session clock, 250 ms while a countdown runs) and calls these with `now`.

public enum SessionTimers {
    /// Whole seconds since the session clock started; nil before it has.
    public static func elapsedSeconds(startedAt: Double?, now: Double) -> Int? {
        guard let startedAt else { return nil }
        return Int(((now - startedAt) / 1000).rounded(.down))
    }

    /// Whether any countdown is running (the web only ticks its 250 ms clock then).
    public static func hasRunningTimer(_ logs: [DraftExercise]) -> Bool {
        logs.contains { $0.timerEndsAt != nil }
    }

    /// A finished countdown ticks its own round off. Returns nil when nothing has
    /// expired (so the caller can skip a state write), else the updated logs.
    public static func completeExpiredTimers(_ logs: [DraftExercise], now: Double) -> [DraftExercise]? {
        guard logs.contains(where: { ($0.timerEndsAt ?? .infinity) <= now }) else { return nil }
        return logs.map { ex in
            guard let ends = ex.timerEndsAt, ends <= now else { return ex }
            var out = ex
            out.completedRounds = min(ex.targetRounds, ex.completedRounds + 1)
            out.timerEndsAt = nil
            out.timerPausedRemaining = nil
            return out
        }
    }

    /// Start (or resume) the countdown on item `exIdx`. Unchanged when there's
    /// nothing to count down.
    public static func startTimer(_ logs: [DraftExercise], exIdx: Int, now: Double) -> [DraftExercise] {
        guard logs.indices.contains(exIdx) else { return logs }
        let ex = logs[exIdx]
        let seconds = ex.timerPausedRemaining ?? ex.targetSeconds ?? 0
        guard seconds > 0 else { return logs }
        var out = logs
        out[exIdx].timerEndsAt = now + Double(seconds) * 1000
        out[exIdx].timerPausedRemaining = nil
        return out
    }

    public static func pauseTimer(_ logs: [DraftExercise], exIdx: Int, now: Double) -> [DraftExercise] {
        guard logs.indices.contains(exIdx), let ends = logs[exIdx].timerEndsAt else { return logs }
        var out = logs
        out[exIdx].timerEndsAt = nil
        out[exIdx].timerPausedRemaining = Int(Swift.max(0, ((ends - now) / 1000).rounded(.up)))
        return out
    }

    public static func resetTimer(_ logs: [DraftExercise], exIdx: Int) -> [DraftExercise] {
        guard logs.indices.contains(exIdx) else { return logs }
        var out = logs
        out[exIdx].timerEndsAt = nil
        out[exIdx].timerPausedRemaining = nil
        return out
    }

    /// Seconds shown on a checklist card: live while running, the paused remainder
    /// while paused, else the full hold.
    public static func remainingSeconds(_ ex: DraftExercise, now: Double) -> Int {
        if let ends = ex.timerEndsAt {
            return Int(Swift.max(0, ((ends - now) / 1000).rounded(.up)))
        }
        return ex.timerPausedRemaining ?? ex.targetSeconds ?? 0
    }

    /// A timed card (filling countdown + swipe-to-complete) vs a plain tick row.
    public static func isTimed(_ ex: DraftExercise) -> Bool {
        (ex.targetSeconds ?? 0) > 0 && ex.targetType == .duration
    }
}

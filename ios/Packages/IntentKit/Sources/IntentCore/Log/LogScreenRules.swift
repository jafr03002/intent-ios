import Foundation

// The small pure rules that pages/log.tsx, components/workout/*, StartWorkoutMenu.tsx,
// hooks/useActiveSession.ts and pages/calibration-briefing.tsx compute inline in
// their JSX. Lifted here so the SwiftUI views stay layout-only and the copy is
// tested once.

/// The session in progress, for surfaces outside the logger (the tab bar's live
/// Start disc). Port of `ActiveSessionSummary` in hooks/useActiveSession.ts.
public struct ActiveSessionSummary: Sendable, Equatable, Hashable {
    public var programId: Int
    public var dayNumber: Int
    /// Epoch ms the session clock started; nil for drafts written before timing existed.
    public var startedAt: Double?

    public init(programId: Int, dayNumber: Int, startedAt: Double?) {
        self.programId = programId; self.dayNumber = dayNumber; self.startedAt = startedAt
    }
}

public extension WorkoutSessionStore {
    /// `readKey` in useActiveSession.ts: read-only, but (like the web, through
    /// `resolveActiveSession`) it self-heals a pointer whose draft has expired.
    func activeSessionSummary(userId: String?) -> ActiveSessionSummary? {
        guard let userId, !userId.isEmpty, let active = resolveActiveSession(userId: userId) else { return nil }
        return ActiveSessionSummary(programId: active.pointer.programId, dayNumber: active.pointer.dayNumber,
                                    startedAt: active.draft.startedAt)
    }
}

/// One row of the Start picker (StartWorkoutMenu.tsx).
public struct StartMenuRow: Sendable, Equatable {
    public var dayNumber: Int
    public var title: String
    public var subtitle: String
}

public struct SavedToast: Sendable, Equatable {
    public var title: String
    public var description: String
}

public enum LogScreenRules {
    // MARK: Numbers

    /// A number as JavaScript prints it (`String(82.5)` = "82.5", `String(80)` = "80").
    public static func formatNumber(_ value: Double) -> String { JS.string(value) }

    /// What a boxless set input shows: `value || ""`.
    public static func inputText(_ value: Double) -> String { value == 0 || value.isNaN ? "" : JS.string(value) }

    // MARK: Session

    /// `sessionPrCount`: every set flagged as a PR this session.
    public static func sessionPrCount(_ logs: [DraftExercise]) -> Int {
        logs.reduce(0) { $0 + $1.sets.filter(\.isNewPr).count }
    }

    /// Exercises that will be saved (named ones).
    public static func loggedCount(_ logs: [DraftExercise]) -> Int {
        logs.filter { !JS.trim($0.name).isEmpty }.count
    }

    /// handleFinishClick's gate: every lift set completed and every checklist item
    /// done. False only means Finish warns first; nothing is blocked.
    public static func allItemsComplete(_ logs: [DraftExercise]) -> Bool {
        logs.allSatisfy { ex in
            ex.kind == .checklist ? ex.completedRounds >= ex.targetRounds : ex.sets.allSatisfy(\.completed)
        }
    }

    /// "Finish workout", or "Finish · 2 new PRs" (the button also shows a trophy).
    public static func finishTitle(prCount: Int) -> String {
        prCount > 0 ? "Finish · \(prCount) new PR\(prCount > 1 ? "s" : "")" : "Finish workout"
    }

    /// The header badge: "1 PR" / "3 PRs".
    public static func prBadge(_ prCount: Int) -> String { "\(prCount) PR\(prCount > 1 ? "s" : "")" }

    /// The toast after a successful save.
    public static func savedToast(isCalibration: Bool, prCount: Int, loggedCount: Int) -> SavedToast {
        if isCalibration {
            return SavedToast(title: "Session saved", description: "Your notes go to your coach for the review.")
        }
        let description = prCount > 0
            ? "\(prCount) new PR\(prCount > 1 ? "s" : "")! Nice work."
            : "\(loggedCount) exercise\(loggedCount == 1 ? "" : "s") logged."
        return SavedToast(title: "Workout saved 🎉", description: description)
    }

    /// The web's `showTargets`: a target is a comparison, so it stays hidden until
    /// there's a saved session (nil history = still loading = hidden). Independent
    /// mode always shows them: those numbers are the user's own.
    public static func showTargets(isIndependent: Bool, historyCount: Int?) -> Bool {
        isIndependent || (historyCount ?? 0) > 0
    }

    // MARK: Exercise card

    /// The caps line over an exercise name: "Chest · Unilateral · 3 × 6-8".
    public static func exerciseMeta(_ ex: DraftExercise, showTargets: Bool, calibration: Bool) -> String {
        var out = ex.muscle
        if ex.isUnilateral { out += " · Unilateral" }
        if showTargets || calibration { out += " · \(ex.targetSets) × \(ex.targetReps)" }
        return out
    }

    /// The calibration row's guide: "8-10 reps" / "8-10 reps / side".
    public static func calibrationGuide(_ ex: DraftExercise) -> String {
        "\(ex.targetReps) reps\(ex.isUnilateral ? " / side" : "")"
    }

    /// The notes toggle: "Note saved", "Add a new note" (last session left one), "Add note".
    public static func notesButtonTitle(notes: String, hasPrevNote: Bool) -> String {
        !notes.isEmpty ? "Note saved" : hasPrevNote ? "Add a new note" : "Add note"
    }

    public static func notesPlaceholder(calibration: Bool) -> String {
        calibration
            ? "Anything get in the way? e.g. couldn't find the machine, swapped it, felt off..."
            : "How did this feel? e.g. felt strong, elbow pain, grip gave out..."
    }

    /// "Last session · 26 Oct: " before last time's note.
    public static func lastNotePrefix(_ note: LastNote, timeZone: TimeZone = .current) -> String {
        let date = SessionLogs.formatShortDate(note.date, timeZone: timeZone)
        return "Last session\(date.map { " · \($0)" } ?? ""): "
    }

    /// "100 kg × 7" (+ " / side") on the target line.
    public static func targetText(_ target: SetTarget, weightUnit: String, isUnilateral: Bool) -> String {
        "\(JS.string(target.weight)) \(weightUnit) × \(target.reps)\(isUnilateral ? " / side" : "")"
    }

    // MARK: Checklist

    /// "round 2 of 3", or nil for a single-round item.
    public static func roundLabel(completedRounds: Int, targetRounds: Int) -> String? {
        targetRounds > 1 ? "round \(min(completedRounds + 1, targetRounds)) of \(targetRounds)" : nil
    }

    /// The category label in its accent ("Mobility"), or "Checklist".
    public static func checklistLabel(_ ex: DraftExercise) -> String {
        ChecklistItems.categoryMeta(ex.category)?.label ?? "Checklist"
    }

    public static func checklistAccent(_ ex: DraftExercise) -> ChartToken {
        ChecklistItems.categoryMeta(ex.category)?.token ?? ChecklistItems.accent
    }

    /// The tick's VoiceOver name.
    public static func checklistTickLabel(_ ex: DraftExercise) -> String {
        ex.completedRounds >= ex.targetRounds
            ? "\(ex.name) — done, tap to clear"
            : "\(ex.name) — mark round \(min(ex.completedRounds + 1, ex.targetRounds)) of \(ex.targetRounds) done"
    }

    /// Fill fraction (0...1) of a timed card: how much of the hold has run.
    public static func timedFillFraction(remaining: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, 1 - Double(remaining) / Double(total)))
    }

    /// Fraction of the card's width a swipe must cross to complete a round.
    public static let swipeCommitFraction = 0.55
    /// Travel before the swipe claims an axis.
    public static let swipeAxisSlop = 6.0

    // MARK: Start picker

    /// A picker row: the day's label (or focus) and "N exercises · N sets", lifting
    /// volume only (a checklist item's `sets` is a round count).
    public static func startMenuRow(_ day: ProgramDay) -> StartMenuRow {
        let lifts = day.exercises.filter { $0.kind != .checklist }
        let sets = lifts.reduce(0) { $0 + $1.sets }
        let title = day.label.isEmpty ? day.focus : day.label
        return StartMenuRow(
            dayNumber: day.dayNumber,
            title: title,
            subtitle: "\(lifts.count) \(lifts.count == 1 ? "exercise" : "exercises") · \(sets) \(sets == 1 ? "set" : "sets")"
        )
    }

    /// What a Start press does with no session running (components/layout.tsx).
    public enum StartPress: Sendable, Equatable {
        /// No program, no days, or locked until its start date: go to the program page.
        case goToProgram
        case openPicker
    }

    public static func startPress(program: Program?, today: Date, timeZone: TimeZone = .current) -> StartPress {
        guard let program, !program.days.isEmpty,
              !Calibration.isPreCalibrationLocked(program, today: today, timeZone: timeZone) else { return .goToProgram }
        return .openPicker
    }

    /// Where picking a day goes: calibration sessions open on the briefing (which
    /// starts the session itself); everything else starts now.
    public enum PickRoute: Sendable, Equatable {
        case briefing(dayNumber: Int)
        case startSession(dayNumber: Int)
    }

    public static func pickRoute(program: Program, dayNumber: Int) -> PickRoute {
        Calibration.isCalibrationProgram(program) ? .briefing(dayNumber: dayNumber) : .startSession(dayNumber: dayNumber)
    }
}

/// pages/calibration-briefing.tsx: Jakob's calibration-session rules, one per card,
/// then "Good luck!".
public enum CalibrationBriefing {
    public struct Point: Sendable, Equatable {
        public var title: String
        public var body: String
    }

    public static let points: [Point] = [
        Point(title: "No logging this week",
              body: "Your main focus is finding the machines and giving honest feedback on whatever happens during your sessions."),
        Point(title: "Don't train at max effort",
              body: "Leave a few reps in the tank and focus on execution. Going all in during the first week isn't the goal - once you're ready after the review, we go all in."),
        Point(title: "The order isn't strict",
              body: "Follow the exercise order as well as you can, but it isn't the end of the world if an exercise gets swapped for another."),
        Point(title: "Leave a note if something gets in the way",
              body: "Add a note on that exercise. Your coach will read it and make adjustments if needed."),
        Point(title: "Afterwards, write anything that comes to mind",
              body: "When you finish, you'll get a box for anything about the session. It all goes to your coach for the review."),
    ]

    /// The rules plus the closing "Good luck!" card.
    public static var stepCount: Int { points.count + 1 }

    public static let intro = "Great, you're starting a session. Since you're in calibration, keep these things in mind:"

    /// "Calibration · Upper A".
    public static func eyebrow(dayLabel: String?) -> String {
        guard let dayLabel, !dayLabel.isEmpty else { return "Calibration" }
        return "Calibration · \(dayLabel)"
    }

    /// Not (or no longer) a calibration session, or still locked: the briefing has
    /// nothing to say, so the session starts the ordinary way.
    public static func shouldSkipBriefing(_ program: Program, today: Date, timeZone: TimeZone = .current) -> Bool {
        !Calibration.isCalibrationProgram(program) || Calibration.isPreCalibrationLocked(program, today: today, timeZone: timeZone)
    }
}

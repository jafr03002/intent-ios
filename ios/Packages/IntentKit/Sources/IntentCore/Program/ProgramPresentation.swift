import Foundation

// Pure logic behind the program page's day hero (ProgramWeekView in
// pages/program/shared.tsx) and the post-generation deck
// (components/onboarding/PresentationDeck.tsx + SatisfactionGate.tsx).

/// `SessionDurationStat` from GET /workouts/duration-stats.
public struct DayDurationStat: Sendable, Equatable {
    public var dayLabel: String?
    public var dayNumber: Int
    public var averageSeconds: Int
    public var sampleCount: Int
    public init(dayLabel: String?, dayNumber: Int, averageSeconds: Int, sampleCount: Int) {
        self.dayLabel = dayLabel; self.dayNumber = dayNumber
        self.averageSeconds = averageSeconds; self.sampleCount = sampleCount
    }
}

public enum ProgramWeek {
    /// Checklist items are left out of both hero figures: their `sets` is a round count.
    public static func liftExercises(_ day: ProgramDay) -> [Exercise] {
        day.exercises.filter { $0.kind != .checklist }
    }

    public static func totalSets(_ day: ProgramDay) -> Int {
        liftExercises(day).reduce(0) { $0 + $1.sets }
    }

    /// The "Avg duration" tile: measured only, shown once the day has been trained
    /// `minSessionsForAverage` times. Matched by label when the stat has one, else by number.
    public static func sessionDuration(_ day: ProgramDay, stats: [DayDurationStat]) -> String? {
        let measured = stats.first { s in
            if let label = s.dayLabel { return label == day.label }
            return s.dayNumber == day.dayNumber
        }
        guard let measured, measured.sampleCount >= SessionDuration.minSessionsForAverage else { return nil }
        return SessionDuration.formatSessionLength(Double(measured.averageSeconds))
    }

    /// The roster row's trailing text: "4 × 6-8", or a checklist target ("2 × 2:30").
    public static func rosterTrailing(_ ex: Exercise) -> String? {
        if ex.kind == .checklist { return ChecklistItems.describeTargetWithRounds(ChecklistTarget(ex)) }
        return "\(ex.sets) × \(ex.reps)"
    }

    /// The roster row's subtitle for a lift: "Chest · Triceps" ("—" with no muscle).
    public static func rosterMuscles(_ ex: Exercise) -> String {
        let primary = ex.muscle.isEmpty ? "—" : ex.muscle
        if let secondary = ex.secondaryMuscle, !secondary.isEmpty { return "\(primary) · \(secondary)" }
        return primary
    }
}

// MARK: - Post-generation deck

public enum ProgramFeedbackCategory: String, Sendable, CaseIterable, Codable {
    case trainingDays = "training_days"
    case exercises, sets, split, order
    case sessionLength = "session_length"
    case equipment
    case priorityMuscles = "priority_muscles"
    case overallVolume = "overall_volume"

    public var label: String {
        switch self {
        case .trainingDays: "Training days"
        case .exercises: "Exercises"
        case .sets: "Sets"
        case .split: "Split"
        case .order: "Exercise order"
        case .sessionLength: "Session length"
        case .equipment: "Equipment"
        case .priorityMuscles: "Priority muscles"
        case .overallVolume: "Overall volume"
        }
    }

    /// The "Days per week" choices shown when Training days is picked.
    public static let trainingDayOptions = [2, 3, 4, 5, 6]
}

public struct PresentationPhase: Sendable, Equatable {
    public var phase: String
    public var weeks: String
    public var length: String?
    public var title: String
    public var motive: String
    public var deloads: Bool
}

public struct MuscleVolume: Sendable, Equatable {
    public var muscle: String
    public var sets: Int
}

public enum ProgramPresentation {
    public static let pages = ["letter", "program", "journey", "volume", "sessions", "happy"]

    private static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven"]

    public static func numberWord(_ n: Int) -> String {
        numberWords.indices.contains(n) ? numberWords[n] : String(n)
    }

    public static func capitalise(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }

    /// "upperBack" / "Upper Back" -> "upper back".
    public static func muscleKey(_ m: String) -> String {
        var spaced = ""
        var prev: Unicode.Scalar?
        for u in m.unicodeScalars {
            if let p = prev, p.value >= 97, p.value <= 122, u.value >= 65, u.value <= 90 { spaced.append(" ") }
            spaced.unicodeScalars.append(u)
            prev = u
        }
        var collapsed = ""
        var inSpace = false
        for u in spaced.lowercased().unicodeScalars {
            if JS.isWhitespace(u) {
                if !inSpace { collapsed.append(" ") }
                inSpace = true
            } else {
                collapsed.unicodeScalars.append(u)
                inSpace = false
            }
        }
        return JS.trim(collapsed)
    }

    public static func muscleLabel(_ m: String) -> String { capitalise(muscleKey(m)) }

    public static func joinWithAnd(_ items: [String]) -> String {
        if items.count <= 1 { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    /// The deck's fixed week: the real fixed schedule, else the days laid out in order.
    public static func weekFromSchedule(_ program: Program) -> [ProgramDay?] {
        let byNumber = Dictionary(program.days.map { ($0.dayNumber, $0) }, uniquingKeysWith: { a, _ in a })
        if let s = program.schedule, s.mode == .fixed, s.slots.count == 7 {
            return s.slots.map { n in n.flatMap { byNumber[$0] } }
        }
        var week = [ProgramDay?](repeating: nil, count: 7)
        for (i, d) in program.days.prefix(7).enumerated() { week[i] = d }
        return week
    }

    public static func isRealSchedule(_ program: Program) -> Bool { program.schedule?.mode == .fixed }

    /// The per-goal phase sequence (a display copy of the server's PHASE_TEMPLATES).
    /// Calibration is "a week", never a week count.
    public static func timeline(goal: String) -> [PresentationPhase] {
        let calibration = PresentationPhase(phase: "calibration", weeks: "First", length: nil, title: "Calibration",
                                            motive: "Find your footing while we dial in your calories.", deloads: false)
        switch goal {
        case "gain_weight":
            return [calibration,
                    PresentationPhase(phase: "bulk", weeks: "Weeks 2–27", length: "26 wk", title: "Bulk",
                                      motive: "A steady surplus to build size.", deloads: true)]
        case "lose_weight":
            return [calibration,
                    PresentationPhase(phase: "mini_cut", weeks: "Weeks 2–7", length: "6 wk", title: "Mini cut",
                                      motive: "A short, sharp push to start the fat loss.", deloads: false),
                    PresentationPhase(phase: "deload", weeks: "Week 8", length: "1 wk", title: "Deload",
                                      motive: "A week at maintenance to recover.", deloads: false),
                    PresentationPhase(phase: "diet", weeks: "Weeks 9–22", length: "14 wk", title: "Diet",
                                      motive: "A steady deficit, all the way down.", deloads: false)]
        default:
            return [calibration,
                    PresentationPhase(phase: "maintenance", weeks: "Week 2 →", length: nil, title: "Maintenance",
                                      motive: "Steady training at maintenance until you change your goal.", deloads: false)]
        }
    }

    /// The goal flag's week ("Goal · week 27"), only for weight-change goals.
    public static func goalWeek(goal: String) -> Int? {
        switch goal {
        case "gain_weight": 27
        case "lose_weight": 22
        default: nil
        }
    }

    /// A deload during a bulk lights the bulk row (it's an overlay, not a row).
    public static func isCurrentPhase(_ phase: String, shortTermPhase: String?, goal: String) -> Bool {
        guard let shortTermPhase, !shortTermPhase.isEmpty else { return false }
        if shortTermPhase == "deload" && goal == "gain_weight" { return phase == "bulk" }
        return phase == shortTermPhase
    }

    /// Index of the current row, 0 when none matches.
    public static func currentPhaseIndex(_ phases: [PresentationPhase], shortTermPhase: String?, goal: String) -> Int {
        phases.firstIndex { isCurrentPhase($0.phase, shortTermPhase: shortTermPhase, goal: goal) } ?? 0
    }

    /// Weekly hard sets per muscle (lifts with a muscle only), most first.
    public static func weeklyVolume(_ days: [ProgramDay]) -> [MuscleVolume] {
        var order: [String] = []
        var totals: [String: Int] = [:]
        for day in days {
            for ex in day.exercises where ex.kind != .checklist && !ex.muscle.isEmpty {
                let key = muscleKey(ex.muscle)
                if totals[key] == nil { order.append(key) }
                totals[key, default: 0] += ex.sets
            }
        }
        let rows = order.map { MuscleVolume(muscle: $0, sets: totals[$0] ?? 0) }
        return JS.stableSorted(rows) { a, b in Double(b.sets - a.sets) }
    }

    /// "an hour" for a 50-70 min average, else "N minutes" to the nearest 5; nil with no estimates.
    public static func durationText(_ days: [ProgramDay]) -> String? {
        let durations = days.compactMap(\.estimatedDurationMinutes)
        guard !durations.isEmpty else { return nil }
        let avg = Double(durations.reduce(0, +)) / Double(durations.count)
        if avg >= 50 && avg <= 70 { return "an hour" }
        return "\(Int(JS.round(avg / 5) * 5)) minutes"
    }

    /// "upper lower" / "push / pull / legs": the split, lower-cased, per `/` or `,` part.
    /// NOTE (ported faithfully): an empty part formats as "undefined" (see SplitType.format).
    public static func splitPhrase(_ splitType: String) -> String {
        splitType.split(omittingEmptySubsequences: false) { $0 == "/" || $0 == "," }
            .map { SplitType.format(JS.trim(String($0))).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    /// The "Program" page cards: highlights without any calibration talk.
    public static func highlights(_ program: Program) -> [ProgramHighlight] {
        program.programHighlights.filter { h in
            !"\(h.title) \(h.detail)".lowercased().contains("calibrat")
        }
    }

    /// Priority muscles minus the "No preference" answer.
    public static func focusMuscles(_ priorityMuscles: [String]) -> [String] {
        priorityMuscles.filter { $0 != "No preference" }
    }

    /// "bulk" / "cut" for weight-change goals.
    public static func longTermWord(goal: String) -> String? {
        switch goal {
        case "gain_weight": "bulk"
        case "lose_weight": "cut"
        default: nil
        }
    }
}

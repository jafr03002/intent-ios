import Foundation

// Domain models mirroring lib/api-spec/openapi.yaml, with the schema names and
// field names unchanged so the generated API types (IntentAPI) map onto them 1:1.
// Only the fields the ported logic reads are required to be present; everything
// the spec makes nullable is optional here.
//
// String enums whose TS readers treat unknown values a particular way decode
// leniently to match (see each type).

/// `Exercise.kind` / `LoggedExercise.kind`. Absent on rows written before checklist
/// items existed; the web reads anything that isn't "checklist" as a lift, and so
/// does the decoder.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case lift
    case checklist

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = raw == "checklist" ? .checklist : .lift
    }
}

/// How a checklist item is measured. `none` is a plain tick-off.
public enum TargetType: String, Codable, Sendable, CaseIterable {
    case duration, count, distance, none
}

public enum ChecklistCategory: String, Codable, Sendable, CaseIterable {
    case stretch, mobility, core, breathing, other
}

/// `ProgramShortTermPhase`. `calibration_review` is a legacy value the API never produces.
public enum ShortTermPhase: String, Codable, Sendable, CaseIterable {
    case calibration
    case calibrationReview = "calibration_review"
    case bulk, maintenance
    case reverseDiet = "reverse_diet"
    case diet
    case miniCut = "mini_cut"
    case deload
}

public enum LongTermPhase: String, Codable, Sendable, CaseIterable {
    case gainWeight = "gain_weight"
    case loseWeight = "lose_weight"
    case maintain
}

public enum EnergyBalance: String, Codable, Sendable, CaseIterable {
    case surplus, maintenance, deficit
    case highDeficit = "high_deficit"
}

public enum TrainingMode: String, Codable, Sendable, CaseIterable {
    case ai, independent
}

public enum LoggingMode: String, Codable, Sendable, CaseIterable {
    case full, calibration
}

/// `Exercise`: one row of a program day - a lift, or a checklist item.
public struct Exercise: Codable, Sendable, Equatable {
    public var name: String
    /// For a checklist item, the round count.
    public var sets: Int
    /// Human-readable target ("8-12", "AMRAP", "5 min").
    public var reps: String
    public var rpe: Int?
    public var restSeconds: Int?
    public var cue: String?
    public var muscle: String
    public var secondaryMuscle: String?
    public var isUnilateral: Bool?
    public var kind: ItemKind
    public var targetType: TargetType?
    public var targetSeconds: Int?
    public var targetValue: Double?
    public var targetUnit: String?
    /// Kept raw: older/newer clients can store anything here, and the logger narrows
    /// it with `ChecklistItems.parseCategory`.
    public var category: String?

    public init(name: String, sets: Int, reps: String, muscle: String, rpe: Int? = nil, restSeconds: Int? = nil,
                cue: String? = nil, secondaryMuscle: String? = nil, isUnilateral: Bool? = nil, kind: ItemKind = .lift,
                targetType: TargetType? = nil, targetSeconds: Int? = nil, targetValue: Double? = nil,
                targetUnit: String? = nil, category: String? = nil) {
        self.name = name; self.sets = sets; self.reps = reps; self.muscle = muscle; self.rpe = rpe
        self.restSeconds = restSeconds; self.cue = cue; self.secondaryMuscle = secondaryMuscle
        self.isUnilateral = isUnilateral; self.kind = kind; self.targetType = targetType
        self.targetSeconds = targetSeconds; self.targetValue = targetValue; self.targetUnit = targetUnit
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, rpe, restSeconds, cue, muscle, secondaryMuscle, isUnilateral, kind
        case targetType, targetSeconds, targetValue, targetUnit, category
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        sets = try c.decode(Int.self, forKey: .sets)
        reps = try c.decode(String.self, forKey: .reps)
        rpe = try c.decodeIfPresent(Int.self, forKey: .rpe)
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds)
        cue = try c.decodeIfPresent(String.self, forKey: .cue)
        muscle = try c.decode(String.self, forKey: .muscle)
        secondaryMuscle = try c.decodeIfPresent(String.self, forKey: .secondaryMuscle)
        isUnilateral = try c.decodeIfPresent(Bool.self, forKey: .isUnilateral)
        kind = try c.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .lift
        // Unknown target types read as no target, as describeTarget does.
        targetType = (try? c.decodeIfPresent(String.self, forKey: .targetType)).flatMap(TargetType.init(rawValue:))
        targetSeconds = try c.decodeIfPresent(Int.self, forKey: .targetSeconds)
        targetValue = try c.decodeIfPresent(Double.self, forKey: .targetValue)
        targetUnit = try c.decodeIfPresent(String.self, forKey: .targetUnit)
        category = try c.decodeIfPresent(String.self, forKey: .category)
    }
}

public struct ProgramDay: Codable, Sendable, Equatable {
    public var dayNumber: Int
    public var label: String
    public var focus: String
    public var estimatedDurationMinutes: Int?
    public var exercises: [Exercise]

    public init(dayNumber: Int, label: String, focus: String = "", estimatedDurationMinutes: Int? = nil, exercises: [Exercise]) {
        self.dayNumber = dayNumber; self.label = label; self.focus = focus
        self.estimatedDurationMinutes = estimatedDurationMinutes; self.exercises = exercises
    }
}

public struct ProgramHighlight: Codable, Sendable, Equatable {
    public var title: String
    public var detail: String
    public init(title: String, detail: String) { self.title = title; self.detail = detail }
}

public enum ScheduleMode: String, Codable, Sendable, CaseIterable {
    case fixed, rotating
}

/// `ProgramSchedule`: slots hold dayNumbers, nil is a rest slot. `fixed` is 7 slots
/// from Monday; `rotating` is one cycle repeating from the program's startDate.
public struct ProgramSchedule: Codable, Sendable, Equatable {
    public var mode: ScheduleMode
    public var slots: [Int?]
    public init(mode: ScheduleMode, slots: [Int?]) { self.mode = mode; self.slots = slots }
}

public struct TrainingWorkload: Codable, Sendable, Equatable {
    public var daysTrained: Int?
    public var totalVolumeSets: Int?
}

public struct CardioIntensity: Codable, Sendable, Equatable {
    public enum Level: String, Codable, Sendable { case low, moderate, high }
    public var bpmMin: Int?
    public var bpmMax: Int?
    public var level: Level?
}

public struct Program: Codable, Sendable, Equatable {
    public var id: Int
    public var userId: String
    /// NOTE: the API stamps every row with the CURRENT training week, not the row's
    /// own - never use it to date a row (see Calibration.buildPhaseRanges).
    public var weekNumber: Int
    public var programName: String
    public var splitType: String
    public var programHighlights: [ProgramHighlight]
    public var aiGenerated: Bool
    public var days: [ProgramDay]
    public var generatedAt: String
    public var longTermPhase: LongTermPhase?
    public var shortTermPhase: ShortTermPhase?
    public var energyBalance: EnergyBalance?
    public var trainingWorkload: TrainingWorkload?
    public var longTermGoalWeight: Double?
    public var shortTermGoalWeight: Double?
    public var dailyStepTarget: Int?
    public var dailyCalorieTarget: Int?
    public var weekInPhase: Int?
    public var phaseTotalWeeks: Int?
    public var cardioIntensity: CardioIntensity?
    /// Local calendar date (YYYY-MM-DD) the client committed to as day 1.
    public var startDate: String?
    public var schedule: ProgramSchedule?

    public init(id: Int, userId: String = "", weekNumber: Int = 1, programName: String = "", splitType: String = "",
                programHighlights: [ProgramHighlight] = [], aiGenerated: Bool, days: [ProgramDay] = [],
                generatedAt: String, shortTermPhase: ShortTermPhase? = nil, weekInPhase: Int? = nil,
                startDate: String? = nil, schedule: ProgramSchedule? = nil) {
        self.id = id; self.userId = userId; self.weekNumber = weekNumber; self.programName = programName
        self.splitType = splitType; self.programHighlights = programHighlights; self.aiGenerated = aiGenerated
        self.days = days; self.generatedAt = generatedAt; self.shortTermPhase = shortTermPhase
        self.weekInPhase = weekInPhase; self.startDate = startDate; self.schedule = schedule
    }
}

/// `LoggedSet`: a saved set as the API stores it. Unilateral sets carry
/// `repsLeft`/`repsRight` and null `reps`.
public struct LoggedSet: Codable, Sendable, Equatable {
    public var setNumber: Int
    public var weight: Double
    public var reps: Int?
    public var repsLeft: Int?
    public var repsRight: Int?
    public var rpe: Int?
    public var completed: Bool
    public var isNewPr: Bool?

    public init(setNumber: Int, weight: Double, reps: Int? = nil, repsLeft: Int? = nil, repsRight: Int? = nil,
                rpe: Int? = nil, completed: Bool = true, isNewPr: Bool? = nil) {
        self.setNumber = setNumber; self.weight = weight; self.reps = reps; self.repsLeft = repsLeft
        self.repsRight = repsRight; self.rpe = rpe; self.completed = completed; self.isNewPr = isNewPr
    }
}

/// `LoggedExercise`: one exercise of a saved workout. A checklist item has no sets.
public struct LoggedExercise: Codable, Sendable, Equatable {
    public var name: String
    public var muscle: String
    public var sets: [LoggedSet]
    public var notes: String?
    public var kind: ItemKind
    public var completedRounds: Int?
    public var targetSeconds: Int?
    public var category: ChecklistCategory?

    public init(name: String, muscle: String, sets: [LoggedSet], notes: String? = nil, kind: ItemKind = .lift,
                completedRounds: Int? = nil, targetSeconds: Int? = nil, category: ChecklistCategory? = nil) {
        self.name = name; self.muscle = muscle; self.sets = sets; self.notes = notes; self.kind = kind
        self.completedRounds = completedRounds; self.targetSeconds = targetSeconds; self.category = category
    }

    enum CodingKeys: String, CodingKey { case name, muscle, sets, notes, kind, completedRounds, targetSeconds, category }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        muscle = try c.decode(String.self, forKey: .muscle)
        sets = try c.decode([LoggedSet].self, forKey: .sets)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        kind = try c.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .lift
        completedRounds = try c.decodeIfPresent(Int.self, forKey: .completedRounds)
        targetSeconds = try c.decodeIfPresent(Int.self, forKey: .targetSeconds)
        category = (try? c.decodeIfPresent(String.self, forKey: .category)).flatMap(ChecklistCategory.init(rawValue:))
    }
}

/// `WorkoutLog`: a saved session. (`calibrationFeedback` is not mirrored - nothing
/// in IntentCore reads it.)
public struct WorkoutLog: Codable, Sendable, Equatable {
    public var id: Int
    public var userId: String
    public var date: String
    public var dayNumber: Int
    public var weekNumber: Int
    public var dayLabel: String?
    public var mode: TrainingMode
    public var loggingMode: LoggingMode
    public var exercisesLogged: [LoggedExercise]
    public var notes: String?
    public var startedAt: String?
    public var durationSeconds: Int?
    public var createdAt: String

    public init(id: Int = 0, userId: String = "", date: String, dayNumber: Int = 1, weekNumber: Int = 1,
                dayLabel: String? = nil, mode: TrainingMode = .ai, loggingMode: LoggingMode = .full,
                exercisesLogged: [LoggedExercise], notes: String? = nil, startedAt: String? = nil,
                durationSeconds: Int? = nil, createdAt: String = "") {
        self.id = id; self.userId = userId; self.date = date; self.dayNumber = dayNumber; self.weekNumber = weekNumber
        self.dayLabel = dayLabel; self.mode = mode; self.loggingMode = loggingMode; self.exercisesLogged = exercisesLogged
        self.notes = notes; self.startedAt = startedAt; self.durationSeconds = durationSeconds; self.createdAt = createdAt
    }
}

/// `WorkoutLogInput`: the body of POST /workouts. (`calibrationFeedback` is left to
/// the calibration screens.)
public struct WorkoutLogInput: Codable, Sendable, Equatable {
    public var date: String
    public var dayNumber: Int
    public var weekNumber: Int
    public var dayLabel: String?
    public var exercisesLogged: [LoggedExercise]
    public var notes: String?
    public var loggingMode: LoggingMode
    public var startedAt: String?
    public var durationSeconds: Int?
}

/// `PersonalRecord`.
public struct PersonalRecord: Codable, Sendable, Equatable {
    public var exercise: String
    public var maxWeight: Double
    public var reps: Int?
    public var date: String

    public init(exercise: String, maxWeight: Double, reps: Int? = nil, date: String = "") {
        self.exercise = exercise; self.maxWeight = maxWeight; self.reps = reps; self.date = date
    }
}

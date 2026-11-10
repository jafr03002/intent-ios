import Foundation

// Port of the manual program builder's logic from pages/program/shared.tsx
// (ManualProgramBuilder and its helpers): the editable shape of a program, the
// save-gate validation, the draft "has changes" check and the save mapping.
// View state (focus, sheets, the draft's storage) stays in the app's Program feature.
//
// NOTE (ported faithfully): `serializeBuilderState` - and so the dirty check, the
// draft write and `programDraftHasChanges` - ignores every checklist field (kind,
// track-by, duration, amount, unit, category). Changing only a checklist item's
// target therefore does not count as unsaved work on the web either.

/// One editable row: a lift or a checklist item (`EditExercise` on the web).
/// Numbers stay strings while editing, as the web's inputs hold them.
public struct ProgramEditExercise: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity for SwiftUI lists; not part of the web shape and not serialised.
    public var id = UUID()
    public var name: String
    public var sets: String
    public var reps: String
    public var muscle: String
    public var secondaryMuscle: String
    public var isUnilateral: Bool
    public var kind: ItemKind
    public var targetType: TargetType
    /// Seconds, straight from the min/sec wheel - the unit the API stores.
    public var durationSeconds: Int
    public var targetValue: String
    public var targetUnit: String
    public var category: String

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, muscle, secondaryMuscle, isUnilateral, kind, targetType
        case durationSeconds, targetValue, targetUnit, category
    }

    public init(name: String = "", sets: String, reps: String, muscle: String = "", secondaryMuscle: String = "",
                isUnilateral: Bool = false, kind: ItemKind, targetType: TargetType = .none, durationSeconds: Int = 0,
                targetValue: String = "", targetUnit: String = "m", category: String = "") {
        self.name = name; self.sets = sets; self.reps = reps; self.muscle = muscle
        self.secondaryMuscle = secondaryMuscle; self.isUnilateral = isUnilateral; self.kind = kind
        self.targetType = targetType; self.durationSeconds = durationSeconds; self.targetValue = targetValue
        self.targetUnit = targetUnit; self.category = category
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.name == b.name && a.sets == b.sets && a.reps == b.reps && a.muscle == b.muscle
            && a.secondaryMuscle == b.secondaryMuscle && a.isUnilateral == b.isUnilateral && a.kind == b.kind
            && a.targetType == b.targetType && a.durationSeconds == b.durationSeconds
            && a.targetValue == b.targetValue && a.targetUnit == b.targetUnit && a.category == b.category
    }
}

public struct ProgramEditDay: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var label: String
    public var exercises: [ProgramEditExercise]

    enum CodingKeys: String, CodingKey { case label, exercises }

    public init(label: String = "", exercises: [ProgramEditExercise]) {
        self.label = label; self.exercises = exercises
    }

    public static func == (a: Self, b: Self) -> Bool { a.label == b.label && a.exercises == b.exercises }
}

/// The one field currently blocking a save. `exercise` is nil when it's the day's name.
public struct ProgramFieldError: Sendable, Equatable {
    public enum Field: String, Sendable { case label, name, sets }
    public var day: Int
    public var exercise: Int?
    public var field: Field
    public var message: String
}

/// A localStorage draft of the builder (`ProgramDraft`). `savedAt` is epoch ms.
public struct ProgramDraft: Codable, Sendable, Equatable {
    public var programName: String
    public var days: [ProgramEditDay]
    public var savedAt: Double
    public init(programName: String, days: [ProgramEditDay], savedAt: Double) {
        self.programName = programName; self.days = days; self.savedAt = savedAt
    }
}

public enum ProgramBuilder {
    public static let missingFieldMessage = "Missing fields above - fill them in before saving."
    /// Drafts older than a day are discarded.
    public static let draftMaxAgeMs: Double = 24 * 60 * 60 * 1000

    /// A new lift row: 2 sets of 8-12 ("Section 1: default sets to 2").
    public static func newExercise() -> ProgramEditExercise {
        ProgramEditExercise(sets: "2", reps: "8-12", kind: .lift)
    }

    /// A plain tick-off: one round, no target, no category.
    public static func newChecklistItem() -> ProgramEditExercise {
        ProgramEditExercise(sets: "1", reps: "", kind: .checklist)
    }

    /// What the builder opens on when creating: one blank day with one blank lift.
    public static func blankDays() -> [ProgramEditDay] {
        [ProgramEditDay(exercises: [newExercise()])]
    }

    public static func editDays(from days: [ProgramDay]) -> [ProgramEditDay] {
        days.map { d in
            ProgramEditDay(label: d.label, exercises: d.exercises.map { e in
                let checklist = e.kind == .checklist
                return ProgramEditExercise(
                    name: e.name,
                    sets: String(e.sets),
                    reps: e.reps,
                    muscle: e.muscle,
                    secondaryMuscle: e.secondaryMuscle ?? "",
                    isUnilateral: e.isUnilateral ?? false,
                    kind: checklist ? .checklist : .lift,
                    targetType: e.targetType ?? .none,
                    // Clamped to what the wheel can express.
                    durationSeconds: Swift.min(Swift.max(0, e.targetSeconds ?? 0), ChecklistItems.maxWheelSeconds),
                    targetValue: e.targetValue.map { JS.string($0) } ?? "",
                    targetUnit: e.targetUnit ?? "m",
                    category: e.category ?? ""
                )
            })
        }
    }

    /// The first field blocking a save, one at a time: a day's name, an item's name,
    /// a lift's set count (blank is an error) or a checklist item's rounds (blank is fine).
    public static func findInvalidField(_ days: [ProgramEditDay]) -> ProgramFieldError? {
        let limit = FieldLimits.sets
        for (di, day) in days.enumerated() {
            if JS.trim(day.label).isEmpty {
                return ProgramFieldError(day: di, exercise: nil, field: .label, message: missingFieldMessage)
            }
            for (ei, ex) in day.exercises.enumerated() {
                if JS.trim(ex.name).isEmpty {
                    return ProgramFieldError(day: di, exercise: ei, field: .name, message: missingFieldMessage)
                }
                if ex.kind == .checklist {
                    if !JS.trim(ex.sets).isEmpty, let m = FieldLimits.rangeError(ex.sets, limit) {
                        return ProgramFieldError(day: di, exercise: ei, field: .sets, message: m)
                    }
                    continue
                }
                let message = JS.trim(ex.sets).isEmpty
                    ? "Enter \(limit.article.rawValue) \(limit.noun) between \(JS.string(limit.min)) and \(JS.string(limit.max))."
                    : FieldLimits.rangeError(ex.sets, limit)
                if let message {
                    return ProgramFieldError(day: di, exercise: ei, field: .sets, message: message)
                }
            }
        }
        return nil
    }

    /// Canonical, whitespace-independent form of a builder state (see the NOTE above:
    /// checklist fields are not part of it).
    public static func serializeBuilderState(programName: String, days: [ProgramEditDay]) -> String {
        let shape: [Any] = [
            JS.trim(programName),
            days.map { d -> [Any] in
                [JS.trim(d.label), d.exercises.map { e -> [Any] in
                    [JS.trim(e.name), JS.trim(e.sets), JS.trim(e.reps), e.muscle, e.secondaryMuscle, e.isUnilateral]
                }]
            },
        ]
        let data = (try? JSONSerialization.data(withJSONObject: shape, options: [])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The saved program (or one blank day when creating), serialised.
    public static func baselineBuilderState(programName: String?, days: [ProgramDay]?) -> String {
        if let programName, let days {
            return serializeBuilderState(programName: programName, days: editDays(from: days))
        }
        return serializeBuilderState(programName: "", days: blankDays())
    }

    /// True only for a draft holding work the program doesn't already have.
    public static func draftHasChanges(_ draft: ProgramDraft?, programName: String?, days: [ProgramDay]?) -> Bool {
        guard let draft else { return false }
        return serializeBuilderState(programName: draft.programName, days: draft.days)
            != baselineBuilderState(programName: programName, days: days)
    }

    /// A stored draft, or nil once it is older than a day.
    public static func freshDraft(_ draft: ProgramDraft?, nowMs: Double) -> ProgramDraft? {
        guard let draft else { return nil }
        return nowMs - draft.savedAt > draftMaxAgeMs ? nil : draft
    }

    /// `traintent:program-draft:<userId>:<programId|new>`.
    public static func draftKey(userId: String, programId: Int?) -> String {
        "traintent:program-draft:\(userId):\(programId.map(String.init) ?? "new")"
    }

    /// The muscle reminder: a named lift with no primary muscle (checklist items excluded).
    public static func hasUnsetMuscle(_ days: [ProgramEditDay]) -> Bool {
        days.contains { d in
            d.exercises.contains { $0.kind != .checklist && !JS.trim($0.name).isEmpty && $0.muscle.isEmpty }
        }
    }

    /// The days as the save request sends them (`performSave`). Only call once
    /// `findInvalidField` is clean.
    public static func programDays(_ days: [ProgramEditDay]) -> [ProgramDay] {
        days.enumerated().map { i, d in
            let label = JS.trim(d.label)
            return ProgramDay(dayNumber: i + 1, label: label, focus: label, exercises: d.exercises.map(saveExercise))
        }
    }

    static func saveExercise(_ e: ProgramEditExercise) -> Exercise {
        if e.kind == .checklist {
            let targetSeconds: Int? = e.targetType == .duration ? e.durationSeconds : nil
            let parsedRounds = JS.parseInt(e.sets, radix: 10)
            let rounds = parsedRounds.isNaN || parsedRounds == 0 ? 1 : Int(parsedRounds)
            var targetValue: Double?
            if (e.targetType == .count || e.targetType == .distance) && !JS.trim(e.targetValue).isEmpty {
                targetValue = ChecklistItems.clampTargetValue(JS.number(e.targetValue), targetType: e.targetType)
            }
            let reps = ChecklistItems.describeTarget(ChecklistTarget(
                targetType: e.targetType, targetSeconds: targetSeconds, targetValue: targetValue, targetUnit: e.targetUnit
            )) ?? ""
            let unit: String? = e.targetType == .distance ? e.targetUnit : e.targetType == .count ? "reps" : nil
            return Exercise(
                name: JS.trim(e.name), sets: rounds, reps: reps, muscle: "", rpe: nil, restSeconds: nil, cue: nil,
                secondaryMuscle: nil, isUnilateral: false, kind: .checklist, targetType: e.targetType,
                targetSeconds: targetSeconds, targetValue: targetValue, targetUnit: unit,
                category: e.category.isEmpty ? nil : e.category
            )
        }
        let sets = JS.parseInt(e.sets, radix: 10)
        return Exercise(
            name: JS.trim(e.name), sets: sets.isNaN ? 0 : Int(sets), reps: e.reps, muscle: e.muscle,
            secondaryMuscle: e.secondaryMuscle.isEmpty ? nil : e.secondaryMuscle,
            isUnilateral: e.isUnilateral, kind: .lift
        )
    }

    /// `programName || "My Program"`.
    public static func saveName(_ programName: String) -> String {
        programName.isEmpty ? "My Program" : programName
    }

    /// `editProgram?.splitType || "Custom"`.
    public static func saveSplitType(_ existing: String?) -> String {
        guard let existing, !existing.isEmpty else { return "Custom" }
        return existing
    }
}

/// The builder's editable state and its edit operations, as ManualProgramBuilder's
/// setState handlers do them.
public struct ProgramBuilderState: Sendable, Equatable {
    public var programName: String
    public var days: [ProgramEditDay]
    public var fieldError: ProgramFieldError?

    public init(programName: String, days: [ProgramEditDay], fieldError: ProgramFieldError? = nil) {
        self.programName = programName; self.days = days; self.fieldError = fieldError
    }

    /// Opens on a restored draft if there is one (with the same error flag a Save
    /// would have raised), else the program being edited, else one blank day.
    public init(draft: ProgramDraft?, editing program: Program?) {
        if let draft {
            self.init(programName: draft.programName, days: draft.days,
                      fieldError: ProgramBuilder.findInvalidField(draft.days))
        } else if let program {
            self.init(programName: program.programName, days: ProgramBuilder.editDays(from: program.days))
        } else {
            self.init(programName: "", days: ProgramBuilder.blankDays())
        }
    }

    public var serialized: String { ProgramBuilder.serializeBuilderState(programName: programName, days: days) }

    public mutating func moveDay(from: Int, to: Int) {
        guard from != to, days.indices.contains(from), to >= 0, to < days.count else { return }
        let moved = days.remove(at: from)
        days.insert(moved, at: to)
    }

    public mutating func addDay() { days.append(ProgramEditDay(exercises: [ProgramBuilder.newExercise()])) }

    public mutating func removeDay(_ di: Int) {
        guard days.indices.contains(di) else { return }
        days.remove(at: di)
    }

    public mutating func setDayLabel(_ di: Int, _ value: String) {
        guard days.indices.contains(di) else { return }
        days[di].label = value
        if let e = fieldError, e.field == .label, e.day == di, !JS.trim(value).isEmpty { fieldError = nil }
    }

    public mutating func addExercise(_ di: Int) {
        guard days.indices.contains(di) else { return }
        days[di].exercises.append(ProgramBuilder.newExercise())
    }

    public mutating func addChecklistItem(_ di: Int) {
        guard days.indices.contains(di) else { return }
        days[di].exercises.append(ProgramBuilder.newChecklistItem())
    }

    public mutating func removeExercise(_ di: Int, _ ei: Int) {
        guard days.indices.contains(di), days[di].exercises.indices.contains(ei) else { return }
        days[di].exercises.remove(at: ei)
    }

    public mutating func moveExercise(_ di: Int, _ ei: Int, by dir: Int) {
        guard days.indices.contains(di) else { return }
        let target = ei + dir
        guard days[di].exercises.indices.contains(ei), days[di].exercises.indices.contains(target) else { return }
        days[di].exercises.swapAt(ei, target)
    }

    /// Several fields at once (the library pick sets name and muscle together). Clears
    /// the error flag as soon as the flagged field of this row is made valid.
    public mutating func patchExercise(_ di: Int, _ ei: Int, _ change: (inout ProgramEditExercise) -> Void) {
        guard days.indices.contains(di), days[di].exercises.indices.contains(ei) else { return }
        let before = days[di].exercises[ei]
        change(&days[di].exercises[ei])
        let after = days[di].exercises[ei]
        guard let e = fieldError, e.day == di, e.exercise == ei else { return }
        switch e.field {
        case .label: return
        case .name:
            if after.name != before.name, !JS.trim(after.name).isEmpty { fieldError = nil }
        case .sets:
            if after.sets != before.sets, !JS.trim(after.sets).isEmpty,
               FieldLimits.rangeError(after.sets, FieldLimits.sets) == nil { fieldError = nil }
        }
    }

    /// Switching how an item is measured clears the previous measure's value.
    public mutating func setTargetType(_ di: Int, _ ei: Int, _ type: TargetType) {
        patchExercise(di, ei) { ex in
            ex.targetType = type
            if type != .duration { ex.durationSeconds = 0 }
            if type != .count && type != .distance { ex.targetValue = "" }
        }
    }

    /// The Save gate: flags the first bad field (returns false), else clears the flag.
    public mutating func validateForSave() -> Bool {
        if let invalid = ProgramBuilder.findInvalidField(days) {
            fieldError = invalid
            return false
        }
        fieldError = nil
        return true
    }
}

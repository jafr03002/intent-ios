import Foundation

// Port of lib/workoutSession.ts: the in-progress workout session.
//
// There is no server-side representation of one, so "a session is in progress"
// means only that a draft plus a pointer to it exist in local storage. Storage is
// injected (`KeyValueStore`), and so is the clock (`now`), so every rule here is
// testable. The JSON written is the web's shape, field for field.

/// One set row in the logger. (TS: `LoggedSet` in workoutSession.ts - renamed so it
/// doesn't collide with the API's `LoggedSet`.)
public struct DraftSet: Codable, Sendable, Equatable {
    public var setNumber: Int
    public var weight: Double
    public var reps: Int
    public var repsLeft: Int
    public var repsRight: Int
    public var completed: Bool
    public var isNewPr: Bool

    public init(setNumber: Int, weight: Double = 0, reps: Int = 0, repsLeft: Int = 0, repsRight: Int = 0,
                completed: Bool = false, isNewPr: Bool = false) {
        self.setNumber = setNumber; self.weight = weight; self.reps = reps; self.repsLeft = repsLeft
        self.repsRight = repsRight; self.completed = completed; self.isNewPr = isNewPr
    }
}

/// One exercise card in the logger. (TS: `LoggedExercise` in workoutSession.ts.)
public struct DraftExercise: Codable, Sendable, Equatable {
    public var name: String
    public var muscle: String
    public var isUnilateral: Bool
    /// Always empty for a checklist item, so it never reaches the volume/e1RM/PR maths.
    public var sets: [DraftSet]
    public var targetSets: Int
    public var targetReps: String
    public var notes: String
    public var showNotes: Bool
    public var kind: ItemKind
    public var targetType: TargetType?
    public var targetSeconds: Int?
    public var targetValue: Double?
    public var targetUnit: String?
    public var category: ChecklistCategory?
    /// Rounds ticked off so far, 0...targetRounds.
    public var completedRounds: Int
    public var targetRounds: Int
    /// Wall-clock epoch ms at which the running countdown expires - an absolute
    /// timestamp, never a decrementing counter, so a suspended app resumes showing
    /// the right value. Nil when idle or paused.
    public var timerEndsAt: Double?
    /// Seconds left while paused, so Resume picks up where Pause left off.
    public var timerPausedRemaining: Int?

    public init(name: String, muscle: String, isUnilateral: Bool = false, sets: [DraftSet] = [], targetSets: Int = 0,
                targetReps: String = "", notes: String = "", showNotes: Bool = false, kind: ItemKind = .lift,
                targetType: TargetType? = nil, targetSeconds: Int? = nil, targetValue: Double? = nil,
                targetUnit: String? = nil, category: ChecklistCategory? = nil, completedRounds: Int = 0,
                targetRounds: Int = 1, timerEndsAt: Double? = nil, timerPausedRemaining: Int? = nil) {
        self.name = name; self.muscle = muscle; self.isUnilateral = isUnilateral; self.sets = sets
        self.targetSets = targetSets; self.targetReps = targetReps; self.notes = notes; self.showNotes = showNotes
        self.kind = kind; self.targetType = targetType; self.targetSeconds = targetSeconds
        self.targetValue = targetValue; self.targetUnit = targetUnit; self.category = category
        self.completedRounds = completedRounds; self.targetRounds = targetRounds; self.timerEndsAt = timerEndsAt
        self.timerPausedRemaining = timerPausedRemaining
    }
}

public struct WorkoutDraft: Codable, Sendable, Equatable {
    public var logs: [DraftExercise]
    /// Epoch ms of the last save.
    public var savedAt: Double
    /// Epoch ms the session clock started. Optional: drafts written before session
    /// timing existed don't carry one.
    public var startedAt: Double?

    public init(logs: [DraftExercise], savedAt: Double, startedAt: Double? = nil) {
        self.logs = logs; self.savedAt = savedAt; self.startedAt = startedAt
    }
}

public struct ActiveSessionPointer: Codable, Sendable, Equatable, Hashable {
    public var programId: Int
    public var dayNumber: Int
    public init(programId: Int, dayNumber: Int) { self.programId = programId; self.dayNumber = dayNumber }
}

/// The localStorage stand-in. Every method is best-effort, like the web's
/// try/catch-wrapped calls: a failing write is simply not readable afterwards.
public protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func removeValue(forKey key: String)
}

/// In-memory store for tests and previews. `refusesWrites` simulates a browser that
/// refuses localStorage (private mode, full quota).
public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private var values: [String: String]
    private let lock = NSLock()
    public var refusesWrites: Bool

    public init(_ values: [String: String] = [:], refusesWrites: Bool = false) {
        self.values = values
        self.refusesWrites = refusesWrites
    }

    public func string(forKey key: String) -> String? { lock.withLock { values[key] } }
    public func set(_ value: String, forKey key: String) {
        lock.withLock { if !refusesWrites { values[key] = value } }
    }
    public func removeValue(forKey key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
    public var allValues: [String: String] { lock.withLock { values } }
}

public enum WorkoutSession {
    /// Drafts older than a day are discarded.
    public static let draftMaxAgeMs: Double = 24 * 60 * 60 * 1000

    /// Keyed on programId + day only: `weekNumber` is a live calendar calculation
    /// that can roll over mid-session, so it can't identify a draft.
    public static func draftKey(userId: String, programId: Int, dayNumber: Int) -> String {
        "traintent:workout-draft:\(userId):\(programId):\(dayNumber)"
    }

    public static func activeSessionKey(userId: String) -> String {
        "traintent:workout-draft:active:\(userId)"
    }
}

/// The draft + pointer storage rules, over an injected store and clock.
public struct WorkoutSessionStore {
    public let store: KeyValueStore
    /// Epoch ms "now". Injected so expiry is testable.
    public var now: () -> Double
    /// Called whenever the pointer is written or cleared (the web's
    /// `traintent:active-session-changed` window event), so e.g. a tab bar can react.
    public var onActiveSessionChange: (() -> Void)?

    public init(store: KeyValueStore, now: @escaping () -> Double = { (Date().timeIntervalSince1970 * 1000).rounded() },
                onActiveSessionChange: (() -> Void)? = nil) {
        self.store = store
        self.now = now
        self.onActiveSessionChange = onActiveSessionChange
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Nil when missing, unreadable, without a `logs` array, or older than a day.
    public func loadDraft(key: String) -> WorkoutDraft? {
        guard let raw = store.string(forKey: key), !raw.isEmpty, let data = raw.data(using: .utf8),
              let draft = try? Self.decoder.decode(WorkoutDraft.self, from: data) else { return nil }
        if now() - draft.savedAt > WorkoutSession.draftMaxAgeMs { return nil }
        return draft
    }

    public func saveDraft(key: String, logs: [DraftExercise], startedAt: Double?) {
        let draft = WorkoutDraft(logs: logs, savedAt: now(), startedAt: startedAt)
        guard let data = try? Self.encoder.encode(draft), let json = String(data: data, encoding: .utf8) else { return }
        store.set(json, forKey: key)
    }

    public func clearDraft(key: String) {
        store.removeValue(forKey: key)
    }

    public func loadActiveSession(userId: String) -> ActiveSessionPointer? {
        guard let raw = store.string(forKey: WorkoutSession.activeSessionKey(userId: userId)), !raw.isEmpty,
              let data = raw.data(using: .utf8) else { return nil }
        return try? Self.decoder.decode(ActiveSessionPointer.self, from: data)
    }

    public func saveActiveSession(userId: String, pointer: ActiveSessionPointer) {
        if let data = try? Self.encoder.encode(pointer), let json = String(data: data, encoding: .utf8) {
            store.set(json, forKey: WorkoutSession.activeSessionKey(userId: userId))
        }
        onActiveSessionChange?()
    }

    public func clearActiveSession(userId: String) {
        store.removeValue(forKey: WorkoutSession.activeSessionKey(userId: userId))
        onActiveSessionChange?()
    }

    /// Begin a session for a day - the only way one ever starts. Always writes a fresh
    /// empty draft (anything already on the key is an orphan) plus the pointer, and
    /// returns whether the session is actually readable back afterwards: false means
    /// storage refused it, which the caller must say rather than navigate on.
    @discardableResult
    public func startSession(userId: String, programId: Int, dayNumber: Int) -> Bool {
        saveDraft(key: WorkoutSession.draftKey(userId: userId, programId: programId, dayNumber: dayNumber),
                  logs: [], startedAt: now())
        saveActiveSession(userId: userId, pointer: ActiveSessionPointer(programId: programId, dayNumber: dayNumber))
        return resolveActiveSession(userId: userId) != nil
    }

    /// The pointer and its draft, or nil. Self-heals a pointer whose draft has expired
    /// or been cleared, so nil always means "nothing in progress".
    public func resolveActiveSession(userId: String) -> (pointer: ActiveSessionPointer, draft: WorkoutDraft)? {
        guard let pointer = loadActiveSession(userId: userId) else { return nil }
        guard let draft = loadDraft(key: WorkoutSession.draftKey(userId: userId, programId: pointer.programId,
                                                                 dayNumber: pointer.dayNumber)) else {
            clearActiveSession(userId: userId)
            return nil
        }
        return (pointer, draft)
    }

    /// Throw away whatever is in progress: the draft it points at, then the pointer.
    public func discardActiveSession(userId: String) {
        if let pointer = loadActiveSession(userId: userId) {
            clearDraft(key: WorkoutSession.draftKey(userId: userId, programId: pointer.programId, dayNumber: pointer.dayNumber))
        }
        clearActiveSession(userId: userId)
    }
}

import Foundation

// The state machine of hooks/useWorkoutSession.ts, minus React. A view model owns
// one controller per /log screen and calls `sync` whenever the program or user
// changes (the hook's effect deps), `setLogs` for every edit (the hook's mirror
// effect), and `endSession` when the session is finished or cancelled.
//
// It only ever RESUMES a session - sessions are started from the program page via
// WorkoutSessionStore.startSession - with one exception: a Start workout press
// that arrives (`start=1`) without having managed to leave a pointer behind.

/// What the /log URL asked for: `?day=<n>&start=1&resumed=1`.
public struct LogRequest: Sendable, Equatable {
    public var targetDayNumber: Int?
    /// The client pressed Start workout to get here.
    public var startRequested: Bool
    /// The program page's discard dialog answered "Keep" (they tried another day).
    public var resumeRequested: Bool

    public init(targetDayNumber: Int? = nil, startRequested: Bool = false, resumeRequested: Bool = false) {
        self.targetDayNumber = targetDayNumber
        self.startRequested = startRequested
        self.resumeRequested = resumeRequested
    }

    /// From query items, as the hook reads `URLSearchParams` (`day` via parseInt).
    public init(query: [String: String]) {
        let n = query["day"].map { JS.parseInt($0) } ?? .nan
        self.init(targetDayNumber: n.isFinite ? Int(n) : nil,
                  startRequested: query["start"] == "1",
                  resumeRequested: query["resumed"] == "1")
    }

    /// The path the hook navigates to (replacing history) once a request is served.
    public static func path(forDay dayNumber: Int) -> String { "/log?day=\(dayNumber)" }
}

public struct WorkoutSessionController {
    public private(set) var logs: [DraftExercise] = []
    public private(set) var activeDay: ProgramDay?
    /// Nil until the program and user are known; false is the idle screen.
    public private(set) var hasSession: Bool?
    /// A Start press reached the page and storage still refused the session.
    public private(set) var startFailed = false
    /// Latched on: show "finish this session before starting another".
    public private(set) var resumedElsewhere = false
    /// Epoch ms the session clock started.
    public private(set) var startedAt: Double?

    private var initializedSeedKey: String?
    private var currentDraftKey: String?
    private var activeSession: ActiveSessionPointer?
    private var ending = false

    public let sessions: WorkoutSessionStore
    public init(sessions: WorkoutSessionStore) { self.sessions = sessions }

    public struct SyncResult: Sendable, Equatable {
        /// Replace the current URL/request with this one (the hook's
        /// `setLocation(..., { replace: true })`); it also spends start/resumed.
        public var redirect: LogRequest?
        public var redirectPath: String? { redirect?.targetDayNumber.map(LogRequest.path(forDay:)) }
    }

    /// The hook's main effect. Call when the program or user changes, and after
    /// applying a redirect (with the new request).
    @discardableResult
    public mutating func sync(program: Program?, userId: String?, request: LogRequest) -> SyncResult {
        guard let program, let userId, !userId.isEmpty else { return SyncResult() }
        if ending { return SyncResult() }

        var active = sessions.resolveActiveSession(userId: userId)
        func dayOf(_ pointer: ActiveSessionPointer) -> ProgramDay? {
            pointer.programId == program.id ? program.days.first { $0.dayNumber == pointer.dayNumber } : nil
        }
        var sessionDay = active.flatMap { dayOf($0.pointer) }

        // Another program's session, or a day this program no longer has.
        if active != nil && sessionDay == nil {
            sessions.clearActiveSession(userId: userId)
            active = nil
        }

        if active == nil, request.startRequested, let target = request.targetDayNumber,
           let wanted = program.days.first(where: { $0.dayNumber == target }) {
            startFailed = !sessions.startSession(userId: userId, programId: program.id, dayNumber: wanted.dayNumber)
            active = sessions.resolveActiveSession(userId: userId)
            sessionDay = active.flatMap { dayOf($0.pointer) }
        }

        guard let day = sessionDay, let resolved = active else {
            hasSession = false
            activeDay = nil
            setLogsWithoutPersisting([])
            startedAt = nil
            resumedElsewhere = false
            initializedSeedKey = nil
            currentDraftKey = nil
            activeSession = nil
            return SyncResult()
        }

        hasSession = true
        activeDay = day

        let requestedDay = request.targetDayNumber.flatMap { t in program.days.first { $0.dayNumber == t } } ?? program.days.first
        let wasRedirected = requestedDay.map { $0.dayNumber != day.dayNumber } ?? false
        let blockedStart = request.startRequested && request.targetDayNumber != nil && request.targetDayNumber != day.dayNumber
        if request.resumeRequested || blockedStart { resumedElsewhere = true }
        var result = SyncResult()
        if wasRedirected || request.startRequested || request.resumeRequested {
            result.redirect = LogRequest(targetDayNumber: day.dayNumber)
        }

        let key = WorkoutSession.draftKey(userId: userId, programId: program.id, dayNumber: day.dayNumber)
        activeSession = ActiveSessionPointer(programId: program.id, dayNumber: day.dayNumber)

        // Keyed on the day AND its structure, so a program edit reaches an open logger.
        let seedKey = "\(key)::\(SessionLogs.dayStructureKey(day))"
        if initializedSeedKey == seedKey { return result }

        let structureChangedMidSession = currentDraftKey == key
        initializedSeedKey = seedKey
        currentDraftKey = key

        let now = sessions.now()
        if structureChangedMidSession {
            setLogs(SessionLogs.reconcileDraftLogs(logs, day: day, now: now), userId: userId)
            return result
        }
        startedAt = resolved.draft.startedAt ?? now
        setLogs(SessionLogs.reconcileDraftLogs(resolved.draft.logs, day: day, now: now), userId: userId)
        return result
    }

    /// Replace the logs and mirror them to storage (the hook's `[logs]` effect).
    public mutating func setLogs(_ newLogs: [DraftExercise], userId: String?) {
        logs = newLogs
        guard let key = currentDraftKey, !logs.isEmpty, !ending else { return }
        sessions.saveDraft(key: key, logs: logs, startedAt: startedAt ?? sessions.now())
        if let userId, !userId.isEmpty, let pointer = activeSession {
            sessions.saveActiveSession(userId: userId, pointer: pointer)
        }
    }

    private mutating func setLogsWithoutPersisting(_ newLogs: [DraftExercise]) {
        logs = newLogs // an empty list never persists anyway
    }

    /// The session is over - saved or discarded. Latches first so nothing re-seeds or
    /// re-saves it, then drops the draft and the pointer.
    public mutating func endSession(userId: String?) {
        ending = true
        if let key = currentDraftKey { sessions.clearDraft(key: key) }
        if let userId, !userId.isEmpty { sessions.clearActiveSession(userId: userId) }
    }
}

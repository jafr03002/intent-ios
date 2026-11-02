import Foundation
import IntentAPI
import IntentCore
import Observation

/// What the check-in reads (the web's adherence, programs and latest-check-in
/// queries) plus the answers and the submit job.
@MainActor
@Observable
final class CheckinModel {
    // Queries. nil adherence = loading or unavailable (404 before an AI program exists).
    var adherence: IntentSchemas.SessionAdherence?
    var adherenceLoading = true
    /// nil until both programs and the latest check-in have answered (the web shows
    /// the form meanwhile). A failed programs call leaves it nil, as on the web.
    var gate: CheckinGate?

    var step = 0
    var answers = CheckinAnswers()
    var resultMessage: String?
    /// A job from an earlier visit is being picked up instead of asking the week again.
    var resuming = false

    let job: CheckinJobRunner

    init(job: CheckinJobRunner) {
        self.job = job
        resuming = job.resumable != nil
    }

    var steps: [CheckinStep] {
        CheckinFlow.steps(loggedSessions: adherence?.loggedSessions, plannedSessions: adherence?.plannedSessions)
    }
    var safeStep: Int { CheckinFlow.clampedStep(step, count: steps.count) }
    var currentStep: CheckinStep { steps[safeStep] }
    var isLastStep: Bool { safeStep == steps.count - 1 }
    var canAdvance: Bool { CheckinFlow.canAdvance(currentStep, answers) }

    func load(_ client: IntentAPIClient) async {
        let api = client.api
        async let adherenceReq = Self.fetchAdherence(api)
        async let programsReq = Self.fetchPrograms(api)
        async let latestReq = Self.fetchLatest(api)

        adherence = await adherenceReq
        adherenceLoading = false
        let programs = await programsReq
        let latest = await latestReq
        if let programs {
            gate = Calibration.checkinGate(programs.map(Self.phaseRow), latestCheckinAt: latest?.submittedAt)
        }
    }

    /// Mount only: picks up the job an earlier visit left running.
    func resumeIfNeeded() async {
        guard job.resumable != nil else { return }
        await finish { try await self.job.resume() }
        resuming = false
    }

    func submit() async {
        let a = answers
        let input = IntentSchemas.CheckinInput(
            energy: a.energy,
            sleep: a.sleep,
            soreness: a.soreness,
            hungerAppetite: a.hungerAppetite,
            // Continue is disabled until it's answered (the web's `offDayDeviation!`).
            offDayDeviation: a.offDayDeviation ?? false,
            // Only meaningful when the missed-session step was shown.
            // (`missedReason || null`: "" must go out as null, not the generated `_empty_` case.)
            missedSessionReason: a.missedReason.isEmpty
                ? nil : IntentSchemas.CheckinInput.MissedSessionReasonPayload(rawValue: a.missedReason),
            exerciseIssues: CheckinFlow.nullIfEmpty(a.exerciseIssues),
            wentWell: CheckinFlow.nullIfEmpty(a.wentWell),
            didntGoWell: CheckinFlow.nullIfEmpty(a.didntGoWell),
            sleepDecline: CheckinFlow.nullIfEmpty(a.sleepDecline),
            digestionIssues: CheckinFlow.nullIfEmpty(a.digestionIssues),
            notes: CheckinFlow.nullIfEmpty(a.notes)
        )
        await finish { try await self.job.run(input) }
    }

    private func finish(_ work: () async throws -> IntentSchemas.CheckinResult) async {
        do {
            let result = try await work()
            // The web invalidates the current-program query here; screens on iOS
            // reload when they appear.
            resultMessage = result.aiMessage
        } catch {
            // A failure shows in the error line (job.error). Leaving mid-review isn't
            // one: the job carries on and resumes next visit.
        }
    }

    // MARK: Requests (nil = failed or absent)

    nonisolated private static func fetchAdherence(_ api: Client) async -> IntentSchemas.SessionAdherence? {
        try? await api.getCheckinAdherence().ok.body.json
    }

    nonisolated private static func fetchPrograms(_ api: Client) async -> [IntentSchemas.Program]? {
        do { return try await api.listPrograms().ok.body.json } catch {
            appLog.error("checkin: listPrograms failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    nonisolated private static func fetchLatest(_ api: Client) async -> IntentSchemas.Checkin? {
        try? await api.getLatestCheckin().ok.body.json
    }

    nonisolated private static func phaseRow(_ p: IntentSchemas.Program) -> PhaseRow {
        let phase = p.shortTermPhase?.rawValue
        return PhaseRow(shortTermPhase: (phase?.isEmpty ?? true) ? nil : phase, weekInPhase: p.weekInPhase,
                        generatedAt: p.generatedAt, aiGenerated: p.aiGenerated, startDate: p.startDate)
    }
}

// MARK: - Job runner

/// Port of hooks/useAiJob.ts for the check-in: start a server-side job, then poll it
/// every 2.5 s instead of holding one POST open for the minute a Claude call takes.
/// The job id is stored (UserDefaults, the web's localStorage key) so leaving the
/// screen or the app being killed mid-review doesn't lose it: the next visit resumes.
@MainActor
@Observable
final class CheckinJobRunner {
    struct StoredJob: Codable, Equatable {
        var jobId: String
        /// Epoch ms, as the web stores it.
        var startedAt: Double
        var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
    }

    private(set) var isPending = false
    private(set) var error: String?
    /// Read once: whether an earlier visit left a job running.
    let resumable: StoredJob?

    @ObservationIgnored private let client: IntentAPIClient
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var wakeUp: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var napID = 0

    static let storageKey = "trainient-ai-job:checkin"

    /// - Parameters:
    ///   - defaults: where the job id is kept; nil disables resuming (mock mode, so one
    ///     CI screenshot can't leave a job behind for the next).
    init(client: IntentAPIClient, pollInterval: Duration = AiJobPolicy.pollInterval, defaults: UserDefaults? = .standard) {
        self.client = client
        self.pollInterval = pollInterval
        self.defaults = defaults
        resumable = Self.readStoredJob(defaults)
    }

    var isError: Bool { error != nil }

    func run(_ input: IntentSchemas.CheckinInput) async throws -> IntentSchemas.CheckinResult {
        isPending = true
        error = nil
        let jobId: String
        do {
            // A retry while a job is still running gets that job back (the server dedupes).
            switch try await client.api.startCheckinJob(body: .json(input)) {
            case .accepted(let ok): jobId = try ok.body.json.jobId
            case .badRequest:
                // The spec gives the 400 no body, so the server's own message ("Complete
                // onboarding first") can't be read; the web shows it when present.
                throw IntentAPIError.http(statusCode: 400, message: nil)
            case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
            }
        } catch {
            isPending = false
            self.error = Self.serverMessage(error) ?? AiJobPolicy.checkinFailureMessage
            throw error
        }
        let job = StoredJob(jobId: jobId, startedAt: (Date().timeIntervalSince1970 * 1000).rounded())
        writeStoredJob(job)
        let result = try await follow(job)
        writeStoredJob(nil)
        return result
    }

    /// Picks up the job an earlier visit left running. Only call when `resumable` is set.
    func resume() async throws -> IntentSchemas.CheckinResult {
        guard let resumable else { throw IntentAPIError.transport("No job to resume") }
        let result = try await follow(resumable)
        writeStoredJob(nil)
        return result
    }

    /// The app came back to the foreground (or back online): poll now rather than
    /// waiting out the nap - timers freeze while a phone is locked.
    func wake() {
        wakeUp?.resume()
        wakeUp = nil
    }

    private func follow(_ job: StoredJob) async throws -> IntentSchemas.CheckinResult {
        generation += 1
        let mine = generation
        isPending = true
        error = nil
        defer { if generation == mine { isPending = false } }
        do {
            while true {
                try await nap()
                let snapshot: IntentSchemas.CheckinJob
                do {
                    switch try await client.api.getCheckinJob(path: .init(jobId: job.jobId)) {
                    case .ok(let ok): snapshot = try ok.body.json
                    case .notFound: throw JobFailure(message: AiJobPolicy.checkinFailureMessage)
                    case .undocumented(let code, let payload):
                        throw await IntentAPIError.undocumented(statusCode: code, payload)
                    }
                } catch let failure as JobFailure {
                    throw failure
                } catch {
                    // Offline, a dropped connection, a cold function: none of these say
                    // anything about the job, so keep asking until the server's own
                    // timeout would have ended it.
                    if AiJobPolicy.hasGivenUp(startedAt: job.startedDate) {
                        throw JobFailure(message: AiJobPolicy.checkinFailureMessage)
                    }
                    continue
                }
                if snapshot.status == .succeeded, let result = snapshot.result { return result }
                if snapshot.status == .failed {
                    throw JobFailure(message: snapshot.error ?? AiJobPolicy.checkinFailureMessage)
                }
            }
        } catch is CancellationError {
            // Left the screen: the job carries on server-side and its id stays stored.
            throw CancellationError()
        } catch {
            writeStoredJob(nil)
            self.error = (error as? JobFailure)?.message ?? AiJobPolicy.checkinFailureMessage
            throw error
        }
    }

    /// Waits one poll interval, or less if `wake()` is called.
    private func nap() async throws {
        try Task.checkCancellation()
        let interval = pollInterval
        napID += 1
        let id = napID
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            wakeUp = continuation
            Task { [weak self] in
                try? await Task.sleep(for: interval)
                // A timer from an earlier nap (cut short by wake()) must not end this one.
                guard let self, self.napID == id else { return }
                self.wake()
            }
        }
        try Task.checkCancellation()
    }

    private struct JobFailure: Error { let message: String }

    private static func serverMessage(_ error: any Error) -> String? {
        if case .http(400, let message?) = error as? IntentAPIError { return message }
        return nil
    }

    // MARK: Storage

    private static func readStoredJob(_ defaults: UserDefaults?) -> StoredJob? {
        guard let data = defaults?.data(forKey: storageKey),
              let job = try? JSONDecoder().decode(StoredJob.self, from: data) else { return nil }
        return AiJobPolicy.isResumable(startedAt: job.startedDate) ? job : nil
    }

    private func writeStoredJob(_ job: StoredJob?) {
        guard let defaults else { return }
        if let job, let data = try? JSONEncoder().encode(job) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}

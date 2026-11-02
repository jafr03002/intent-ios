import Foundation
import IntentAPI
import IntentCore
import Observation

/// Runs AI program generation as a server-side job and polls it - the port of the
/// web's `useAiJob` / `useProgramGenerationJob` (hooks/useAiJob.ts). A phone can't
/// hold a POST open for the minute a Claude call takes, so the job id is stored and
/// a later visit resumes it (`resumable`, read once at creation).
///
/// Generic over the job so a check-in poller can reuse it: give it `start` and `read`.
@MainActor
@Observable
final class ProgramAiJobPoller<Input: Sendable, Result: Sendable> {
    struct Snapshot: Sendable {
        enum Status: Sendable { case pending, running, succeeded, failed }
        var status: Status
        var result: Result?
        var error: String?
    }

    /// Thrown when polling stopped because the screen went away (web: `AbortedError`).
    struct Abandoned: Error {}

    struct StoredJob: Codable, Sendable {
        var jobId: String
        /// Epoch ms.
        var startedAt: Double
    }

    struct JobFailure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static var pollInterval: Duration { .milliseconds(2500) }
    /// The server fails a job six minutes after creation; past that a stored id is dead.
    static var giveUpAfterMs: Double { 6.5 * 60 * 1000 }

    let kind: String
    let failureMessage: String
    private let start: @Sendable (Input) async throws -> String
    private let read: @Sendable (String) async throws -> Snapshot?
    private let defaults: UserDefaults

    private(set) var isPending = false
    private(set) var error: String?
    /// Read once: a job an earlier visit left running.
    let resumableJob: StoredJob?
    var resumable: Bool { resumableJob != nil }
    var isError: Bool { error != nil }

    private var generation = 0

    /// - Parameters:
    ///   - start: starts the job and returns its id (throws `JobFailure` with the
    ///     server's message for a 400).
    ///   - read: one poll; nil means "no such job" (404).
    init(kind: String, failureMessage: String, defaults: UserDefaults = .standard,
         start: @escaping @Sendable (Input) async throws -> String,
         read: @escaping @Sendable (String) async throws -> Snapshot?) {
        self.kind = kind
        self.failureMessage = failureMessage
        self.start = start
        self.read = read
        self.defaults = defaults
        resumableJob = Self.readStoredJob(kind: kind, defaults: defaults)
    }

    private var storageKey: String { "trainient-ai-job:\(kind)" }

    private static func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    private static func readStoredJob(kind: String, defaults: UserDefaults) -> StoredJob? {
        guard let data = defaults.data(forKey: "trainient-ai-job:\(kind)"),
              let job = try? JSONDecoder().decode(StoredJob.self, from: data) else { return nil }
        return nowMs() - job.startedAt < giveUpAfterMs ? job : nil
    }

    private func writeStoredJob(_ job: StoredJob?) {
        if let job, let data = try? JSONEncoder().encode(job) {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }

    /// Stops following (the job carries on server-side and stays stored).
    func abandon() { generation += 1; isPending = false }

    private func follow(_ job: StoredJob) async throws -> Result {
        generation += 1
        let mine = generation
        isPending = true
        error = nil
        defer { if generation == mine { isPending = false } }
        do {
            while true {
                try await Task.sleep(for: Self.pollInterval)
                if generation != mine { throw Abandoned() }
                let snapshot: Snapshot?
                do {
                    snapshot = try await read(job.jobId)
                } catch is CancellationError {
                    throw Abandoned()
                } catch {
                    // Offline or a cold function says nothing about the job: keep asking
                    // until the server's own timeout would have ended it.
                    if Self.nowMs() - job.startedAt > Self.giveUpAfterMs { throw JobFailure(message: failureMessage) }
                    continue
                }
                if generation != mine { throw Abandoned() }
                guard let snapshot else { throw JobFailure(message: failureMessage) }
                if snapshot.status == .succeeded, let result = snapshot.result { return result }
                if snapshot.status == .failed { throw JobFailure(message: snapshot.error ?? failureMessage) }
            }
        } catch is CancellationError {
            throw Abandoned()
        } catch let abandoned as Abandoned {
            throw abandoned
        } catch {
            writeStoredJob(nil)
            self.error = (error as? JobFailure)?.message ?? failureMessage
            throw error
        }
    }

    func run(_ input: Input) async throws -> Result {
        isPending = true
        error = nil
        let jobId: String
        do {
            // A retry while a job runs gets that job back (the server dedupes).
            jobId = try await start(input)
        } catch {
            isPending = false
            self.error = (error as? JobFailure)?.message ?? failureMessage
            throw error
        }
        let job = StoredJob(jobId: jobId, startedAt: Self.nowMs())
        writeStoredJob(job)
        let result = try await follow(job)
        writeStoredJob(nil)
        return result
    }

    /// Picks up the job an earlier visit left running. Only call when `resumable`.
    func resume() async throws -> Result {
        guard let resumableJob else { throw JobFailure(message: "No job to resume") }
        let result = try await follow(resumableJob)
        writeStoredJob(nil)
        return result
    }
}

typealias ProgramGenerationPoller = ProgramAiJobPoller<Components.Schemas.GenerateProgramInput?, Program>

extension ProgramAiJobPoller where Input == Components.Schemas.GenerateProgramInput?, Result == Program {
    /// `useProgramGenerationJob`.
    static func programGeneration(_ api: IntentAPIClient) -> ProgramGenerationPoller {
        ProgramGenerationPoller(
            kind: "program_generation",
            failureMessage: "Program generation failed. Please try again.",
            start: { input in
                let body = input.map { Operations.StartProgramGenerationJob.Input.Body.json($0) }
                switch try await api.api.startProgramGenerationJob(body: body) {
                case .accepted(let accepted): return try accepted.body.json.jobId
                case .badRequest:
                    // The spec gives the 400 no body, so the server's own message
                    // ("Complete onboarding first") isn't readable here.
                    throw JobFailure(message: "Program generation failed. Please try again.")
                case .undocumented(let code, let payload):
                    throw await IntentAPIError.undocumented(statusCode: code, payload)
                }
            },
            read: { jobId in
                switch try await api.api.getProgramGenerationJob(path: .init(jobId: jobId)) {
                case .ok(let ok):
                    let job = try ok.body.json
                    let status: Snapshot.Status = switch job.status {
                    case .pending: .pending
                    case .running: .running
                    case .succeeded: .succeeded
                    case .failed: .failed
                    }
                    let result = try job.result.map { try ProgramAPI.bridge($0, to: Program.self) }
                    return Snapshot(status: status, result: result, error: job.error)
                case .notFound: return nil
                case .undocumented(let code, let payload):
                    throw await IntentAPIError.undocumented(statusCode: code, payload)
                }
            }
        )
    }
}

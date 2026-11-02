import Foundation
import IntentAPI
import Observation

/// Port of hooks/useAiJob.ts for program generation: start a server-side job, then
/// poll it every 2.5 s until it succeeds or fails, instead of holding one request
/// open for the minute a Claude call takes. The job id is kept in UserDefaults
/// (the web's localStorage key) so a later visit could pick it up again.
///
/// Differences from the web: there's no early wake on "visibilitychange"/"online"
/// (iOS suspends the task while backgrounded and resumes it on return), and
/// onboarding never calls `resume()` on the web either, so it isn't ported here.
@MainActor
@Observable
final class OnboardingProgramJob {
    typealias ProgramResult = Components.Schemas.Program

    static let failureMessage = "Program generation failed. Please try again."
    static let pollInterval: Duration = .milliseconds(2500)
    /// The server fails a job six minutes after creation; past this a poll loop
    /// that still hasn't heard back has lost the server, not the job.
    static let giveUpAfter: TimeInterval = 6.5 * 60
    static let storageKey = "trainient-ai-job:program_generation"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let api: Client
    private let defaults: UserDefaults
    private(set) var isPending = false
    private(set) var error: String?

    init(api: Client, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
    }

    var isError: Bool { error != nil }

    func run(_ input: Components.Schemas.GenerateProgramInput?) async throws -> ProgramResult {
        isPending = true
        error = nil
        defer { isPending = false }
        let jobId: String
        do {
            // A retry while a job is still running gets that job back - the server dedupes.
            switch try await api.startProgramGenerationJob(body: input.map { .json($0) }) {
            case .accepted(let accepted): jobId = try accepted.body.json.jobId
            case .badRequest: throw Failure(message: Self.failureMessage)
            case .undocumented(let code, let payload):
                let apiError = await IntentAPIError.undocumented(statusCode: code, payload)
                if case .http(_, let message?) = apiError, code == 400 { throw Failure(message: message) }
                throw Failure(message: Self.failureMessage)
            }
        } catch let failure as Failure {
            error = failure.message
            throw failure
        } catch {
            self.error = Self.failureMessage
            throw error
        }
        let startedAt = Date()
        store(jobId: jobId, startedAt: startedAt)
        do {
            let program = try await follow(jobId: jobId, startedAt: startedAt)
            store(jobId: nil, startedAt: nil)
            return program
        } catch is CancellationError {
            // Leaving the screen stops polling; the job carries on server-side.
            throw CancellationError()
        } catch {
            store(jobId: nil, startedAt: nil)
            self.error = (error as? Failure)?.message ?? Self.failureMessage
            throw error
        }
    }

    private func follow(jobId: String, startedAt: Date) async throws -> ProgramResult {
        while true {
            try await Task.sleep(for: Self.pollInterval)
            let job: Components.Schemas.ProgramGenerationJob
            do {
                switch try await api.getProgramGenerationJob(path: .init(jobId: jobId)) {
                case .ok(let ok): job = try ok.body.json
                case .notFound: throw Failure(message: Self.failureMessage)
                case .undocumented:
                    if Date().timeIntervalSince(startedAt) > Self.giveUpAfter { throw Failure(message: Self.failureMessage) }
                    continue
                }
            } catch let failure as Failure {
                throw failure
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Offline, a dropped connection, a cold function: none of these say
                // anything about the job, so keep asking until the server would have ended it.
                if Date().timeIntervalSince(startedAt) > Self.giveUpAfter { throw Failure(message: Self.failureMessage) }
                continue
            }
            if job.status == .succeeded, let result = job.result { return result }
            if job.status == .failed { throw Failure(message: job.error ?? Self.failureMessage) }
        }
    }

    private func store(jobId: String?, startedAt: Date?) {
        if let jobId, let startedAt {
            let ms = Int(startedAt.timeIntervalSince1970 * 1000)
            defaults.set(#"{"jobId":"\#(jobId)","startedAt":\#(ms)}"#, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}

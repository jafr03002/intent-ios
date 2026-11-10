import Foundation
import IntentAPI
import IntentCore

/// The Program feature's calls to the API, mapped onto IntentCore models. Generated
/// schema types are bridged through JSON: their field names are the IntentCore ones.
enum ProgramAPI {
    enum Lineage: String { case ai, manual }

    /// The bits of the profile the program pages read.
    struct Profile: Sendable, Equatable {
        var userId: String
        var name: String?
        var mode: String
        var goal: String
        var experience: String
        var trainingDays: Int
        var weightUnit: String?
        var priorityMuscles: [String]
        var programPageTourSeenAt: String?

        var isIndependent: Bool { mode == "independent" }
        /// AI onboarding is the only place goal/experience get set.
        var aiProfileReady: Bool { !goal.isEmpty && !experience.isEmpty }
    }

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func bridge<From: Encodable, To: Decodable>(_ value: From, to: To.Type) throws -> To {
        try JSONDecoder().decode(To.self, from: JSONEncoder().encode(value))
    }

    static func profile(_ api: IntentAPIClient) async throws -> Profile? {
        switch try await api.api.getProfile() {
        case .ok(let ok):
            let p = try ok.body.json
            return Profile(userId: p.userId, name: p.name, mode: p.mode, goal: p.goal, experience: p.experience,
                           trainingDays: p.trainingDays, weightUnit: p.weightUnit, priorityMuscles: p.priorityMuscles,
                           programPageTourSeenAt: p.programPageTourSeenAt)
        case .notFound: return nil
        case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
        }
    }

    /// The current program of one lineage; nil when it has none (404).
    static func currentProgram(_ api: IntentAPIClient, lineage: Lineage) async throws -> Program? {
        let query = Operations.GetCurrentProgram.Input.Query(lineage: lineage == .ai ? .ai : .manual)
        switch try await api.api.getCurrentProgram(query: query) {
        case .ok(let ok): return try bridge(try ok.body.json, to: Program.self)
        case .notFound: return nil
        case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
        }
    }

    /// Measured per-day session lengths; empty when the call fails (the tile just stays hidden).
    static func durationStats(_ api: IntentAPIClient) async -> [DayDurationStat] {
        guard let out = try? await api.api.getSessionDurationStats(), case .ok(let ok) = out,
              let body = try? ok.body.json else { return [] }
        return body.stats.map {
            DayDurationStat(dayLabel: $0.dayLabel, dayNumber: $0.dayNumber, averageSeconds: $0.averageSeconds,
                            sampleCount: $0.sampleCount)
        }
    }

    /// Settings' per-day colour picks, keyed by day label.
    static func calendarColors(_ api: IntentAPIClient) async -> [String: String] {
        guard let out = try? await api.api.getCalendarColors(), case .ok(let ok) = out,
              let rows = try? ok.body.json else { return [:] }
        var map: [String: String] = [:]
        for row in rows { map[row.dayLabel] = row.hexColor }
        return map
    }

    static func updateProfile(_ api: IntentAPIClient, _ update: Components.Schemas.UserProfileUpdate) async throws {
        switch try await api.api.updateProfile(body: .json(update)) {
        case .ok: return
        case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
        }
    }

    static func markProgramTourSeen(_ api: IntentAPIClient) async {
        var update = Components.Schemas.UserProfileUpdate()
        update.programPageTourSeenAt = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(Date())
        try? await updateProfile(api, update)
    }

    // MARK: - Manual program writes

    static func manualInput(name: String, splitType: String, days: [ProgramDay]) throws -> Components.Schemas.ManualProgramInput {
        Components.Schemas.ManualProgramInput(
            programName: name, splitType: splitType,
            days: try bridge(days, to: [Components.Schemas.ProgramDay].self)
        )
    }

    static func createManualProgram(_ api: IntentAPIClient, _ input: Components.Schemas.ManualProgramInput) async throws -> Program {
        switch try await api.api.createManualProgram(body: .json(input)) {
        case .created(let created): return try bridge(try created.body.json, to: Program.self)
        case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
        }
    }

    /// PUT /programs/{id}. The generated `updateProgram` has a broken URL (the spec's
    /// path is the literal `/programs/:id`, with no parameter) - the web works around
    /// the same bug in its orval client with a direct fetch. The mock backend answers
    /// by operation id, so mock mode uses the generated call; the real API gets the
    /// request built by hand.
    @MainActor
    static func updateProgram(_ services: AppServices, id: Int, _ input: Components.Schemas.ManualProgramInput) async throws -> Program {
        if services.isMock {
            switch try await services.api.api.updateProgram(body: .json(input)) {
            case .ok(let ok): return try bridge(try ok.body.json, to: Program.self)
            case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
            }
        }
        var request = URLRequest(url: services.api.baseURL.appendingPathComponent("programs/\(id)"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try await services.auth.tokenProvider(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(input)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw status == 401 ? IntentAPIError.unauthorized : IntentAPIError.http(statusCode: status, message: message)
        }
        return try JSONDecoder().decode(Program.self, from: data)
    }

    // MARK: - AI generation jobs

    static func feedbackInput(_ feedback: ProgramFeedbackDraft?) -> Components.Schemas.GenerateProgramInput? {
        guard let feedback else { return nil }
        let categories = feedback.categories.compactMap {
            Components.Schemas.ProgramFeedback.CategoriesPayloadPayload(rawValue: $0.rawValue)
        }
        return Components.Schemas.GenerateProgramInput(feedback: .init(categories: categories, note: feedback.note))
    }
}

/// The deck's "Tweak something" answer (`ProgramFeedback` on the web). `trainingDays`
/// is saved to the profile before regenerating; the API itself only takes the rest.
struct ProgramFeedbackDraft: Sendable, Equatable {
    var categories: [ProgramFeedbackCategory]
    var note: String
    var trainingDays: Int?
}

import Foundation
import IntentAPI
import IntentCore
import Observation

/// What the calendar reads from the API (the web's five queries), mapped to IntentCore.
@MainActor
@Observable
final class CalendarData {
    struct ProgramDayRef: Equatable {
        var label: String
        var dayNumber: Int
    }

    var workouts: [WorkoutLog] = []
    /// dayLabel -> user-picked hex.
    var customColors: [String: String] = [:]
    var programDays: [ProgramDayRef] = []
    var schedule: ProgramSchedule?
    var programStartDate: String?
    var programs: [PhaseRow] = []
    var profileLoaded = false
    var isIndependent = false
    var goal: String?
    var onboardingCompletedAt: String?
    var isLoading = true
    var loadFailed = false

    func load(_ client: IntentAPIClient) async {
        let api = client.api
        async let workoutsReq = Self.fetchWorkouts(api)
        async let colorsReq = Self.fetchColors(api)
        async let currentReq = Self.fetchCurrent(api)
        async let programsReq = Self.fetchPrograms(api)
        async let profileReq = Self.fetchProfile(api)

        let fetchedWorkouts = await workoutsReq
        workouts = fetchedWorkouts?.compactMap { CalendarAPIMapping.convert($0, to: WorkoutLog.self) } ?? []
        loadFailed = fetchedWorkouts == nil

        var colors: [String: String] = [:]
        for c in await colorsReq ?? [] { colors[c.dayLabel] = c.hexColor }
        customColors = colors

        if let current = await currentReq {
            programDays = current.days.map { ProgramDayRef(label: $0.label, dayNumber: $0.dayNumber) }
            schedule = CalendarAPIMapping.schedule(current.schedule)
            programStartDate = current.startDate
        } else {
            programDays = []
            schedule = nil
            programStartDate = nil
        }
        programs = (await programsReq ?? []).map(CalendarAPIMapping.phaseRow)

        if let profile = await profileReq {
            profileLoaded = true
            isIndependent = profile.mode == "independent"
            goal = profile.goal
            onboardingCompletedAt = profile.onboardingCompletedAt
        } else {
            profileLoaded = false
        }
        isLoading = false
    }

    /// Workouts only (after a delete), as the web invalidates listWorkouts.
    func reloadWorkouts(_ client: IntentAPIClient) async {
        if let fetched = await Self.fetchWorkouts(client.api) {
            workouts = fetched.compactMap { CalendarAPIMapping.convert($0, to: WorkoutLog.self) }
        }
    }

    func delete(_ id: Int, client: IntentAPIClient) async throws {
        switch try await client.api.deleteWorkout(path: .init(id: id)) {
        case .noContent: break
        case .notFound: throw IntentAPIError.http(statusCode: 404, message: "Not found")
        case .undocumented(let code, let payload): throw await IntentAPIError.undocumented(statusCode: code, payload)
        }
    }

    // MARK: Requests (nil = failed or absent)

    nonisolated private static func fetchWorkouts(_ api: Client) async -> [IntentSchemas.WorkoutLog]? {
        do { return try await api.listWorkouts(query: .init(limit: 200)).ok.body.json } catch {
            appLog.error("calendar: listWorkouts failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    nonisolated private static func fetchColors(_ api: Client) async -> [IntentSchemas.CalendarColor]? {
        try? await api.getCalendarColors().ok.body.json
    }

    nonisolated private static func fetchCurrent(_ api: Client) async -> IntentSchemas.Program? {
        try? await api.getCurrentProgram().ok.body.json
    }

    nonisolated private static func fetchPrograms(_ api: Client) async -> [IntentSchemas.Program]? {
        try? await api.listPrograms().ok.body.json
    }

    nonisolated private static func fetchProfile(_ api: Client) async -> IntentSchemas.UserProfile? {
        try? await api.getProfile().ok.body.json
    }
}

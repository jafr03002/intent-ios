import Foundation
import IntentAPI
import IntentCore
import Observation

/// What the progress page reads (the web's queries), mapped to IntentCore.
///
/// NOTE (web parity): the web also fetches getVolumeProgress but renders nothing
/// from it - the volume card is built from getMuscleVolumeBreakdown - so it isn't
/// fetched here.
@MainActor
@Observable
final class ProgressData {
    var trackedExercises: [String] = []
    var strength: [ProgressMath.StrengthPoint] = []
    var strengthLoading = false
    var records: [PersonalRecord] = []
    var muscleWeeks: [ProgressMath.MuscleWeek] = []
    var bodyweight: [ProgressMath.BodyweightPoint] = []
    var bodyweightLoading = true
    var weightUnit = "kg"
    var goalWeight: Double?

    func load(_ client: IntentAPIClient) async {
        let api = client.api
        async let trackedReq = Self.tracked(api)
        async let prsReq = Self.prs(api)
        async let muscleReq = Self.muscle(api)
        async let bodyReq = Self.bodyweight(api)
        async let profileReq = Self.profile(api)

        trackedExercises = await trackedReq ?? []
        records = (await prsReq ?? []).map {
            PersonalRecord(exercise: $0.exercise, maxWeight: $0.maxWeight, reps: $0.reps, date: $0.date)
        }
        muscleWeeks = (await muscleReq ?? []).map(Self.muscleWeek)
        bodyweight = (await bodyReq ?? []).map { ProgressMath.BodyweightPoint(date: $0.date, weight: $0.weight) }
        bodyweightLoading = false
        if let profile = await profileReq {
            weightUnit = profile.weightUnit ?? "kg"
            goalWeight = profile.goalWeight
        }
    }

    func loadStrength(_ exercise: String, client: IntentAPIClient) async {
        guard !exercise.isEmpty else {
            strength = []
            return
        }
        strengthLoading = true
        let points = (try? await client.api.getStrengthProgress(query: .init(exercise: exercise)).ok.body.json) ?? []
        strength = points.map { ProgressMath.StrengthPoint(date: $0.date, maxWeight: $0.maxWeight, exercise: $0.exercise) }
        strengthLoading = false
    }

    nonisolated private static func muscleWeek(_ w: IntentSchemas.MuscleVolumeWeek) -> ProgressMath.MuscleWeek {
        let pairs: [(String, Int?)] = [
            ("chest", w.chest), ("shoulders", w.shoulders), ("biceps", w.biceps), ("triceps", w.triceps),
            ("upperBack", w.upperBack), ("lats", w.lats), ("quads", w.quads), ("hamstrings", w.hamstrings),
            ("glutes", w.glutes), ("calves", w.calves), ("core", w.core),
        ]
        var sets: [String: Int] = [:]
        for (key, value) in pairs { if let value { sets[key] = value } }
        return ProgressMath.MuscleWeek(week: w.week, sets: sets)
    }

    nonisolated private static func tracked(_ api: Client) async -> [String]? {
        try? await api.listTrackedExercises().ok.body.json
    }

    nonisolated private static func prs(_ api: Client) async -> [IntentSchemas.PersonalRecord]? {
        try? await api.getPersonalRecords().ok.body.json
    }

    nonisolated private static func muscle(_ api: Client) async -> [IntentSchemas.MuscleVolumeWeek]? {
        try? await api.getMuscleVolumeBreakdown().ok.body.json
    }

    nonisolated private static func bodyweight(_ api: Client) async -> [IntentSchemas.BodyweightPoint]? {
        try? await api.getBodyweightProgress().ok.body.json
    }

    nonisolated private static func profile(_ api: Client) async -> IntentSchemas.UserProfile? {
        try? await api.getProfile().ok.body.json
    }
}

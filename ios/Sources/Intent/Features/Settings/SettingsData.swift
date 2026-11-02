import Foundation
import IntentAPI
import IntentCore
import Observation

/// What the "You" tab reads and writes (the web page's seven queries and five
/// mutations, minus checkout: no purchase flow until StoreKit vs Stripe is decided).
@MainActor
@Observable
final class SettingsData {
    var profile: IntentSchemas.UserProfile?
    var subscription: IntentSchemas.Subscription?
    var subscriptionLoading = true
    /// dayLabel -> stored hex.
    var storedColors: [IntentSchemas.CalendarColor] = []
    var currentProgram: IntentSchemas.Program?
    var programs: [IntentSchemas.Program] = []
    var isLoaded = false

    var mode: String { profile?.mode ?? "ai" }
    var isIndependent: Bool { mode == "independent" }
    var isPro: Bool { subscription?.plan == "pro" }

    /// The recolourable days (current program first, then this lineage's stored labels).
    var colorLabels: (labels: [String], order: [String: Int]) {
        SettingsLogic.colorLabels(
            currentProgramLabels: currentProgram?.days.map(\.label) ?? [],
            programs: programs.map { .init(aiGenerated: $0.aiGenerated, labels: $0.days.map(\.label)) },
            storedLabels: storedColors.map(\.dayLabel),
            isIndependent: isIndependent
        )
    }

    func load(_ client: IntentAPIClient) async {
        let api = client.api
        async let profileReq = Self.fetch { try await api.getProfile().ok.body.json }
        async let subReq = Self.fetch { try await api.getSubscription().ok.body.json }
        async let colorsReq = Self.fetch { try await api.getCalendarColors().ok.body.json }
        async let currentReq = Self.fetch { try await api.getCurrentProgram().ok.body.json }
        async let programsReq = Self.fetch { try await api.listPrograms().ok.body.json }
        profile = await profileReq
        // A failed subscription read shows as "Free", like the web's `data?.plan`.
        subscription = await subReq
        subscriptionLoading = false
        storedColors = await colorsReq ?? []
        currentProgram = await currentReq
        programs = await programsReq ?? []
        isLoaded = true
    }

    /// Mode-scoped reads after a mode switch (the web invalidates profile, current
    /// program, stats and the program list).
    func reloadAfterModeSwitch(_ client: IntentAPIClient) async {
        let api = client.api
        async let profileReq = Self.fetch { try await api.getProfile().ok.body.json }
        async let currentReq = Self.fetch { try await api.getCurrentProgram().ok.body.json }
        async let programsReq = Self.fetch { try await api.listPrograms().ok.body.json }
        if let p = await profileReq { profile = p }
        currentProgram = await currentReq
        programs = await programsReq ?? programs
    }

    // MARK: Writes (throw on any non-2xx)

    func saveProfile(_ patch: SettingsLogic.ProfilePatch, client: IntentAPIClient) async throws {
        let body = IntentSchemas.UserProfileUpdate(name: patch.name, age: patch.age, weight: patch.weight, weightUnit: patch.weightUnit)
        profile = try await client.api.updateProfile(body: .json(body)).ok.body.json
    }

    func switchMode(to mode: String, client: IntentAPIClient) async throws {
        _ = try await client.api.updateProfile(body: .json(.init(mode: mode))).ok
        await reloadAfterModeSwitch(client)
    }

    func upsertColor(label: String, hex: String, client: IntentAPIClient) async throws {
        let saved = try await client.api.upsertCalendarColor(body: .json(.init(dayLabel: label, hexColor: hex))).ok.body.json
        storedColors.removeAll { $0.dayLabel == saved.dayLabel }
        storedColors.append(saved)
    }

    /// DELETE /account: application data only. The Clerk user is deleted afterwards by
    /// the caller (see SettingsScreen.deleteAccount).
    func deleteAccount(client: IntentAPIClient) async throws {
        _ = try await client.api.deleteAccount().noContent
    }

    func portalURL(client: IntentAPIClient) async throws -> URL? {
        URL(string: try await client.api.createPortalSession().ok.body.json.url)
    }

    nonisolated private static func fetch<T: Sendable>(_ op: @Sendable () async throws -> T) async -> T? {
        do { return try await op() } catch {
            appLog.error("settings: read failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

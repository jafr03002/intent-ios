import Foundation
import Testing
@testable import IntentAPI

/// The Program feature's fixtures (the write operations in default/ and the
/// program-independent scenario) must decode through the generated client.
@Suite struct FixturesProgramTests {
    let client = IntentAPIClient(environment: .production, transport: FixtureTransport(latency: .zero))
    let independent = IntentAPIClient(
        environment: .production, transport: FixtureTransport(scenario: "program-independent", latency: .zero))

    private var manualInput: Components.Schemas.ManualProgramInput {
        .init(programName: "My Program", splitType: "Custom", days: [
            .init(dayNumber: 1, label: "Push", focus: "Push", exercises: [
                .init(name: "Bench", sets: 3, reps: "8", muscle: "Chest"),
            ]),
        ])
    }

    @Test func programWritesDecode() async throws {
        let updated = try await client.api.updateProgram(body: .json(manualInput)).ok.body.json
        #expect(updated.id == 9 && updated.aiGenerated == false)
        #expect(updated.days.contains { $0.exercises.contains { $0.kind == .checklist } })
        let created = try await client.api.createManualProgram(body: .json(manualInput)).created.body.json
        #expect(created.programName == "My Push Pull Legs")
        let started = try await client.api.setProgramStartDate(
            path: .init(id: 12), body: .json(.init(startDate: "2026-11-02"))).ok.body.json
        #expect(started.id == 12)
        let generated = try await client.api.generateProgram().created.body.json
        #expect(generated.aiGenerated && generated.id == 13)
    }

    @Test func generationJobDecodes() async throws {
        let accepted = try await client.api.startProgramGenerationJob().accepted.body.json
        let job = try await client.api.getProgramGenerationJob(path: .init(jobId: accepted.jobId)).ok.body.json
        #expect(job.status == .succeeded)
        #expect(job.result?.days.count == 4)
        #expect(job.error == nil)
    }

    @Test func independentScenarioDecodes() async throws {
        let profile = try await independent.api.getProfile().ok.body.json
        #expect(profile.mode == "independent" && profile.name == "Alex")
        let program = try await independent.api.getCurrentProgram(query: .init(lineage: .manual)).ok.body.json
        #expect(program.id == 9 && program.programName == "My Push Pull Legs" && !program.aiGenerated)
        #expect(program.days.map(\.label) == ["Push", "Pull", "Legs"])
        let stats = try await independent.api.getSessionDurationStats().ok.body.json
        #expect(stats.stats.first?.sampleCount == 4)
        let colors = try await independent.api.getCalendarColors().ok.body.json
        #expect(colors.first?.dayLabel == "Legs")
        // Everything else falls back to default/.
        #expect(try await independent.api.listPrograms().ok.body.json.count == 2)
    }
}

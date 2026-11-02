import Foundation
import IntentCore

/// The builder's crash/reload safety net (the web's localStorage program draft),
/// in UserDefaults under the same key shape.
enum ProgramDraftStore {
    static func load(userId: String, programId: Int?, defaults: UserDefaults = .standard) -> ProgramDraft? {
        let key = ProgramBuilder.draftKey(userId: userId, programId: programId)
        guard let data = defaults.data(forKey: key),
              let draft = try? JSONDecoder().decode(ProgramDraft.self, from: data) else { return nil }
        return ProgramBuilder.freshDraft(draft, nowMs: nowMs())
    }

    static func save(userId: String, programId: Int?, programName: String, days: [ProgramEditDay],
                     defaults: UserDefaults = .standard) {
        let draft = ProgramDraft(programName: programName, days: days, savedAt: nowMs())
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: ProgramBuilder.draftKey(userId: userId, programId: programId))
    }

    static func clear(userId: String, programId: Int?, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: ProgramBuilder.draftKey(userId: userId, programId: programId))
    }

    private static func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }
}

import Foundation

// Port of the pure half of lib/nextSet.ts (scrollToSet is DOM glue and stays out).

public struct SetPosition: Sendable, Equatable, Hashable, Codable {
    public var exIdx: Int
    public var setIdx: Int
    public init(exIdx: Int, setIdx: Int) { self.exIdx = exIdx; self.setIdx = setIdx }
}

public enum NextSet {
    /// The set to log next: the first not-yet-completed lift set in page order.
    /// Checklist items are skipped. Nil when every lift set is done.
    public static func findNextUnloggedSet(_ logs: [DraftExercise]) -> SetPosition? {
        for (exIdx, ex) in logs.enumerated() where ex.kind != .checklist {
            if let setIdx = ex.sets.firstIndex(where: { !$0.completed }) {
                return SetPosition(exIdx: exIdx, setIdx: setIdx)
            }
        }
        return nil
    }

    public static func hasAnyLoggedSet(_ logs: [DraftExercise]) -> Bool {
        logs.contains { $0.kind != .checklist && $0.sets.contains(where: \.completed) }
    }
}

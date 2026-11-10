import Foundation

// Port of lib/exerciseLibrary.ts: the picker's exercise catalogue (transcribed from
// docs/exercise-arsenal.md) and its search. Keyed by primary muscle; an exercise may
// appear under two groups (dips: Chest and Triceps). The parity tests compare this
// data against the TS module, entry for entry.

public struct LibraryExercise: Sendable, Equatable, Hashable, Codable {
    public var name: String
    public var muscle: Muscle
    public init(name: String, muscle: Muscle) { self.name = name; self.muscle = muscle }
}

public struct LibraryGroup: Sendable, Equatable {
    public var muscle: Muscle
    public var names: [String]
}

public enum ExerciseLibrary {
    public static let byMuscle: [Muscle: [String]] = [
        .chest: [
            "Dumbbell Bench Press", "Barbell Bench Press", "Incline Dumbbell Press", "Incline Barbell Press",
            "Pec Fly Machine", "Pec Fly Cable", "Pec Fly Dumbbell", "Dips", "Machine Dips", "Weighted Dips",
            "Decline Dumbbell Press", "Decline Barbell Press", "Machine Flat Chest Press",
            "Machine Incline Chest Press", "Machine Decline Chest Press", "Flat Smith Press",
            "Incline Smith Press", "Decline Smith Press",
        ],
        .shoulders: [
            // Full delt
            "Shoulder Overhead Dumbbell Press", "Shoulder Overhead Barbell Press",
            "Shoulder Overhead Machine Press", "Shoulder Overhead Smith Press",
            // Side delt
            "Dumbbell Lateral Raises", "Machine Lateral Raises", "Cable Lateral Raises", "Y-Raise",
            // Rear delt
            "Pec Dec Rear Delt Flies", "Dumbbell Rear Delt Flies", "Cable Rear Delt Flies",
        ],
        .biceps: [
            "Machine Preacher Curl", "Standing Dumbbell Curl", "Incline Bench Dumbbell Curl", "Preacher Bench Curl",
            "Barbell Curl", "Cable EZ-Bar Curl", "Cable D-Handle Curl", "Cable Drag Curl", "Dumbbell Hammer Curl",
            "Rope Hammer Cable Curl", "Hammer Machine Curl",
        ],
        .triceps: [
            "Dips", "Machine Dips", "Weighted Dips", "Tricep Pushdown", "Skullcrushers", "Overhead Tricep Extension",
        ],
        .upperBack: [
            "Machine Row", "Smith Machine Row", "Barbell Row", "T-Bar Row", "Landmine Row", "Dumbbell Row",
            "Cable Row", "High Machine Row", "High Cable Row", "Smith High Row",
        ],
        .lats: [
            "Cable Wide Pulldown", "Cable Close-Grip Pulldown", "Machine Wide Pulldown",
            "Machine Close-Grip Pulldown", "Cable Lat Row", "Machine Lat Row", "SA Bench Lat Pulldown",
            "SA Machine Lat Pulldown",
        ],
        .quads: [
            "Leg Press", "Barbell Squat", "Smith Machine Squat", "Hack Squat", "Pendulum Squat", "Hip Press",
            "Leg Extension", "Bulgarian Split Squat",
            // The arsenal's lone "Adductors" entry - there is no adductor group.
            "Adductor Machine",
        ],
        .hamstrings: [
            "Seated Hamstring Curl", "Lying Hamstring Curl", "45 Degree Hinge", "Romanian Deadlift",
            "Stiff Leg Deadlift", "Deadlift",
        ],
        .glutes: [
            "Hip Thrust", "Banded 45 Degree Hinge", "Abduction Machine", "Glute Kickback",
            "Glute Biased Bulgarian Split Squat Dumbbell", "Glute Biased Bulgarian Split Squat Smith",
        ],
        .calves: ["Standing Calf Raise", "Seated Calf Raise", "Toe Press"],
        .core: ["Plank", "Cable Crunch", "Machine Crunch", "Hanging Leg Raises", "Lying Leg Raises", "Pallof Press"],
    ]

    private struct Indexed: Sendable {
        let exercise: LibraryExercise
        let lowerName: String
        let lowerMuscle: String
        let words: [String]
    }

    private static func wordsOf(_ lowerName: String) -> [String] {
        // split(/[^a-z0-9]+/).filter(Boolean)
        var words: [String] = []
        var current = ""
        for u in lowerName.unicodeScalars {
            let v = u.value
            if (v >= 97 && v <= 122) || (v >= 48 && v <= 57) {
                current.unicodeScalars.append(u)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static let index: [Indexed] = Muscle.allCases.flatMap { muscle in
        (byMuscle[muscle] ?? []).map { name in
            let lower = JS.lower(name)
            return Indexed(exercise: LibraryExercise(name: name, muscle: muscle), lowerName: lower,
                           lowerMuscle: JS.lower(muscle.rawValue), words: wordsOf(lower))
        }
    }

    /// Every entry, in muscle-group order then list order.
    public static let allExercises: [LibraryExercise] = index.map(\.exercise)

    /// Muscle groups that have exercises, in `Muscle.allCases` order.
    public static let groups: [LibraryGroup] = Muscle.allCases.compactMap { m in
        let names = byMuscle[m] ?? []
        return names.isEmpty ? nil : LibraryGroup(muscle: m, names: names)
    }

    private static func tokenTier(_ token: String, _ ex: Indexed) -> Int? {
        if ex.words.contains(where: { $0.hasPrefix(token) }) { return 0 }
        if ex.lowerName.contains(token) || ex.lowerMuscle.contains(token) { return 1 }
        return nil
    }

    /// Ranked matches for what the user has typed. Every whitespace-separated token
    /// must match; the whole query prefixing the name ranks first, then all-word-prefix
    /// matches, then substring hits - alphabetical (ICU order) within each tier.
    public static func search(_ query: String, limit: Int = 40) -> [LibraryExercise] {
        let trimmed = JS.lower(JS.trim(query))
        if trimmed.isEmpty { return [] }
        let tokens = splitOnWhitespace(trimmed)
        var scored: [(ex: Indexed, tier: Int)] = []
        for ex in index {
            var tier = 0
            var matched = true
            for token in tokens {
                guard let t = tokenTier(token, ex) else { matched = false; break }
                tier = max(tier, t)
            }
            if !matched { continue }
            if ex.lowerName.hasPrefix(trimmed) { tier = -1 }
            scored.append((ex, tier))
        }
        let sorted = JS.stableSorted(scored) { a, b in
            if a.tier != b.tier { return Double(a.tier - b.tier) }
            return Double(JS.localeCompare(a.ex.exercise.name, b.ex.exercise.name))
        }
        return sorted.prefix(max(0, limit)).map(\.ex.exercise)
    }

    /// `str.split(/\s+/)` on an already-trimmed, non-empty string.
    static func splitOnWhitespace(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inSpace = false
        for u in s.unicodeScalars {
            if JS.isWhitespace(u) {
                if !inSpace { out.append(current); current = "" }
                inSpace = true
            } else {
                inSpace = false
                current.unicodeScalars.append(u)
            }
        }
        out.append(current)
        return out
    }
}

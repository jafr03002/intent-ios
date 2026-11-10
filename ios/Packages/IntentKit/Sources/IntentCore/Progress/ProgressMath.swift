import Foundation

// Port of the pure parts of pages/progress.tsx: number formatting, the hidden chart
// axes' bounds, the volume card's ranking and weekly totals, and the "new PR"
// recency test. The views live in the app's Features/Progress.

public enum ProgressMath {
    /// `StrengthPoint`.
    public struct StrengthPoint: Sendable, Equatable, Codable {
        public var date: String
        public var maxWeight: Double
        public var exercise: String?
        public init(date: String, maxWeight: Double, exercise: String? = nil) {
            self.date = date; self.maxWeight = maxWeight; self.exercise = exercise
        }
    }

    /// `BodyweightPoint`.
    public struct BodyweightPoint: Sendable, Equatable, Codable {
        public var date: String
        public var weight: Double
        public init(date: String, weight: Double) { self.date = date; self.weight = weight }
    }

    /// `MuscleVolumeWeek`: sets per muscle key for one training week.
    public struct MuscleWeek: Sendable, Equatable {
        public var week: Int
        public var sets: [String: Int]
        public init(week: Int, sets: [String: Int]) { self.week = week; self.sets = sets }
        public func sets(_ key: String) -> Int { sets[key] ?? 0 }
    }

    public struct RankedMuscle: Sendable, Equatable {
        public var key: String
        public var label: String
        public var sets: Int
        /// vs the week before (0 when there is none).
        public var change: Int
    }

    public struct WeekTotal: Sendable, Equatable {
        public var week: Int
        public var sets: Int
    }

    public struct Bounds: Sendable, Equatable {
        public var lower: Double
        public var upper: Double
    }

    /// Keys match the MuscleVolumeWeek schema, in display order.
    public static let muscleGroups: [(key: String, label: String)] = [
        ("chest", "Chest"), ("shoulders", "Shoulders"), ("biceps", "Biceps"), ("triceps", "Triceps"),
        ("upperBack", "Upper Back"), ("lats", "Lats"), ("quads", "Quads"), ("hamstrings", "Hamstrings"),
        ("glutes", "Glutes"), ("calves", "Calves"), ("core", "Core"),
    ]

    /// How many of the ranked muscles get the white "lead" bar.
    public static let leadMuscles = 3
    /// Weeks shown in the volume card's "All weeks" view.
    public static let volumeHistoryWeeks = 8

    // MARK: Formatting

    /// One decimal at most, so 2.5 kg steps survive but float noise doesn't.
    public static func fmt(_ n: Double) -> String { JS.string(JS.round(n * 10) / 10) }

    /// "+2.5", "−1" (a real minus sign), "±0".
    public static func signed(_ n: Double) -> String {
        if n > 0 { return "+\(fmt(n))" }
        if n < 0 { return "\u{2212}\(fmt(abs(n)))" }
        return "±0"
    }

    /// "26 Oct" - `new Date(dateStr)` (so a bare date is UTC midnight, as on the web).
    public static func shortDate(_ date: String, timeZone tz: TimeZone = .current) -> String {
        SessionLogs.formatShortDate(date, timeZone: tz) ?? "Invalid Date"
    }

    /// "26 Oct 2026".
    public static func shortDateWithYear(_ date: String, timeZone tz: TimeZone = .current) -> String {
        guard let p = JSDate.localParts(JSDate.parse(date, tz), tz) else { return "Invalid Date" }
        return "\(p.day) \(SessionLogs.enGBShortMonths[p.month0]) \(p.year)"
    }

    /// Within `days` days before `now` (`new Date(dateStr)`, so a bare date is UTC midnight).
    public static func isRecent(_ date: String, now: Date, days: Double = 7, timeZone tz: TimeZone = .current) -> Bool {
        (JSDate.ms(now) - JSDate.parse(date, tz)) / JSDate.msPerDay <= days
    }

    public static func recentPrCount(_ prs: [PersonalRecord], now: Date, timeZone tz: TimeZone = .current) -> Int {
        prs.filter { isRecent($0.date, now: now, timeZone: tz) }.count
    }

    /// Newest first (`b.date.localeCompare(a.date)`, stable).
    public static func sortedRecords(_ prs: [PersonalRecord]) -> [PersonalRecord] {
        JS.stableSorted(prs) { a, b in Double(JS.localeCompare(b.date, a.date)) }
    }

    // MARK: Chart bounds

    /// Strength axis: ~75% of the lowest weight up to the top weight, snapped to 5s.
    public static func strengthBounds(_ weights: [Double]) -> Bounds? {
        guard let lo = weights.min(), let hi = weights.max() else { return nil }
        return Bounds(lower: max(0, JS.round(lo * 0.75 / 5) * 5), upper: (hi / 5).rounded(.up) * 5)
    }

    /// Bodyweight axis on its own scale (2 kg snaps), with the goal folded in so its
    /// line is always framed.
    public static func bodyweightBounds(_ weights: [Double], goalWeight: Double?) -> Bounds? {
        guard !weights.isEmpty else { return nil }
        var all = weights
        if let goalWeight { all.append(goalWeight) }
        let lo = all.min()!, hi = all.max()!
        return Bounds(lower: max(0, (lo * 0.98 / 2).rounded(.down) * 2), upper: (hi * 1.02 / 2).rounded(.up) * 2)
    }

    /// "5.6 kg to go" vs "Goal reached".
    public static func goalLine(current: Double?, goalWeight: Double, unit: String) -> String {
        guard let current else { return "Goal reached" }
        let toGoal = abs(current - goalWeight)
        return toGoal >= 0.05 ? "\(fmt(toGoal)) \(unit) to go" : "Goal reached"
    }

    // MARK: Volume

    public static func weekTotal(_ week: MuscleWeek?) -> Int {
        guard let week else { return 0 }
        return muscleGroups.reduce(0) { $0 + week.sets($1.key) }
    }

    /// The latest week's muscles with sets, most first (stable), each vs the week before.
    public static func rankedMuscles(latest: MuscleWeek?, prior: MuscleWeek?) -> [RankedMuscle] {
        let all = muscleGroups.map { g in
            RankedMuscle(key: g.key, label: g.label, sets: latest?.sets(g.key) ?? 0,
                         change: (latest?.sets(g.key) ?? 0) - (prior?.sets(g.key) ?? 0))
        }.filter { $0.sets > 0 }
        return JS.stableSorted(all) { a, b in Double(b.sets - a.sets) }
    }

    /// The last `volumeHistoryWeeks` weeks' totals, oldest first.
    public static func weeklyTotals(_ weeks: [MuscleWeek]) -> [WeekTotal] {
        weeks.suffix(volumeHistoryWeeks).map { WeekTotal(week: $0.week, sets: weekTotal($0)) }
    }
}

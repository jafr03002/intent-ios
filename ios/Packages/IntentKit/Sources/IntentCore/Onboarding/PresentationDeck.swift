import Foundation

// Port of the pure parts of components/onboarding/PresentationDeck.tsx and
// CommitmentScreen.tsx: the coach's-letter wording helpers, the phase timeline,
// weekly volume, the week grid, and the start-day quick picks / month grid.

public enum PresentationDeck {
    public enum Page: String, Sendable, CaseIterable {
        case letter, program, journey, volume, sessions, happy
    }

    static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven"]

    public static func numberWord(_ n: Int) -> String {
        numberWords.indices.contains(n) ? numberWords[n] : String(n)
    }

    public static func capitalise(_ s: String) -> String {
        guard let first = s.first else { return "" }
        return first.uppercased() + s.dropFirst()
    }

    /// `m.replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase().replace(/\s+/g, " ").trim()`:
    /// "upperBack" and "Upper Back" both become "upper back".
    public static func muscleKey(_ m: String) -> String {
        var spaced = String.UnicodeScalarView()
        var prev: Unicode.Scalar?
        for u in m.unicodeScalars {
            if let p = prev, p.value >= 0x61, p.value <= 0x7A, u.value >= 0x41, u.value <= 0x5A { spaced.append(" ") }
            spaced.append(u)
            prev = u
        }
        let lowered = String(spaced).lowercased()
        var collapsed = ""
        var inSpace = false
        for u in lowered.unicodeScalars {
            if JS.isWhitespace(u) {
                if !inSpace { collapsed.append(" ") }
                inSpace = true
            } else {
                collapsed.unicodeScalars.append(u)
                inSpace = false
            }
        }
        return JS.trim(collapsed)
    }

    public static func muscleLabel(_ m: String) -> String { capitalise(muscleKey(m)) }

    /// "a", "a and b", "a, b and c".
    public static func joinWithAnd(_ items: [String]) -> String {
        if items.count <= 1 { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    /// `splitType.split(/[\/,]/).map(formatSplitType(trim).toLowerCase()).filter(Boolean).join(" / ")`.
    public static func splitText(_ splitType: String) -> String {
        splitType.split(omittingEmptySubsequences: false) { $0 == "/" || $0 == "," }
            .map { part -> String in
                let trimmed = JS.trim(String(part))
                // formatSplitType("") is the literal "undefined" on the web - and truthy.
                return SplitType.format(trimmed).lowercased()
            }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    /// The real fixed schedule as 7 Monday-first slots, or the days laid out in order.
    public static func week(_ program: Program) -> [ProgramDay?] {
        let byNumber = Dictionary(program.days.map { ($0.dayNumber, $0) }, uniquingKeysWith: { _, last in last })
        if let schedule = program.schedule, schedule.mode == .fixed, schedule.slots.count == 7 {
            return schedule.slots.map { n in n.flatMap { byNumber[$0] } }
        }
        var week: [ProgramDay?] = Array(repeating: nil, count: 7)
        for (i, d) in program.days.prefix(7).enumerated() { week[i] = d }
        return week
    }

    public static func isRealSchedule(_ program: Program) -> Bool { program.schedule?.mode == .fixed }

    public struct Phase: Sendable, Equatable {
        public var phase: String
        public var weeks: String
        public var length: String?
        public var title: String
        public var motive: String
        public var deloads: Bool
    }

    /// The per-goal phase sequence (display copy of the server's PHASE_TEMPLATES).
    /// Calibration is "a week" with no count; later phases are numbered from week 2.
    public static func timeline(goal: String) -> [Phase] {
        let calibration = Phase(phase: "calibration", weeks: "First", length: nil, title: "Calibration",
                                motive: "Find your footing while we dial in your calories.", deloads: false)
        switch goal {
        case "gain_weight":
            return [calibration,
                    Phase(phase: "bulk", weeks: "Weeks 2–27", length: "26 wk", title: "Bulk",
                          motive: "A steady surplus to build size.", deloads: true)]
        case "lose_weight":
            return [calibration,
                    Phase(phase: "mini_cut", weeks: "Weeks 2–7", length: "6 wk", title: "Mini cut",
                          motive: "A short, sharp push to start the fat loss.", deloads: false),
                    Phase(phase: "deload", weeks: "Week 8", length: "1 wk", title: "Deload",
                          motive: "A week at maintenance to recover.", deloads: false),
                    Phase(phase: "diet", weeks: "Weeks 9–22", length: "14 wk", title: "Diet",
                          motive: "A steady deficit, all the way down.", deloads: false)]
        default:
            return [calibration,
                    Phase(phase: "maintenance", weeks: "Week 2 →", length: nil, title: "Maintenance",
                          motive: "Steady training at maintenance until you change your goal.", deloads: false)]
        }
    }

    public static func goalWeek(_ goal: String) -> Int? {
        ["gain_weight": 27, "lose_weight": 22][goal]
    }

    /// A deload during a bulk lights the bulk row.
    public static func isCurrentPhase(_ phase: String, shortTermPhase: String?, goal: String) -> Bool {
        guard let short = shortTermPhase, !short.isEmpty else { return false }
        if short == "deload" && goal == "gain_weight" { return phase == "bulk" }
        return phase == short
    }

    public static func currentIndex(_ phases: [Phase], shortTermPhase: String?, goal: String) -> Int {
        max(0, phases.firstIndex { isCurrentPhase($0.phase, shortTermPhase: shortTermPhase, goal: goal) } ?? -1)
    }

    public struct MuscleVolume: Sendable, Equatable {
        public var muscle: String
        public var sets: Int
    }

    /// Weekly hard sets per muscle (checklist items and muscle-less rows skipped),
    /// most first; ties keep first-seen order (JS sort is stable).
    public static func weeklyVolume(_ days: [ProgramDay]) -> [MuscleVolume] {
        var order: [String] = []
        var totals: [String: Int] = [:]
        for day in days {
            for ex in day.exercises where ex.kind != .checklist && !ex.muscle.isEmpty {
                let key = muscleKey(ex.muscle)
                if totals[key] == nil { order.append(key) }
                totals[key, default: 0] += ex.sets
            }
        }
        let rows = order.map { MuscleVolume(muscle: $0, sets: totals[$0]!) }
        return JS.stableSorted(rows) { a, b in Double(b.sets - a.sets) }
    }

    /// "an hour" for a 50-70 minute average, else the average to the nearest 5.
    public static func durationText(_ days: [ProgramDay]) -> String? {
        let durations = days.compactMap(\.estimatedDurationMinutes)
        guard !durations.isEmpty else { return nil }
        let avg = Double(durations.reduce(0, +)) / Double(durations.count)
        if avg >= 50 && avg <= 70 { return "an hour" }
        return "\(JS.string(JS.round(avg / 5) * 5)) minutes"
    }

    /// Highlights minus any that talk about calibration (Jakob: no calibration talk here).
    public static func highlights(_ program: Program) -> [ProgramHighlight] {
        program.programHighlights.filter { !"\($0.title) \($0.detail)".lowercased().contains("calibrat") }
    }

    /// The focus muscles without "No preference".
    public static func focus(_ priorityMuscles: [String]) -> [String] {
        priorityMuscles.filter { $0 != "No preference" }
    }

    /// "bulk" / "cut" / nil (maintenance) for the letter's sentence.
    public static func longTerm(goal: String) -> String? {
        goal == "gain_weight" ? "bulk" : goal == "lose_weight" ? "cut" : nil
    }
}

public enum StartDayPicker {
    public struct QuickPick: Sendable, Equatable {
        public var key: String
        public var title: String
        public var date: Date
    }

    static func calendar(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.firstWeekday = 2
        return c
    }

    /// Today, Tomorrow, and next Monday unless it's already one of those
    /// (date-fns `nextMonday` is always strictly after today).
    public static func quickPicks(today: Date, timeZone: TimeZone = .current) -> [QuickPick] {
        let cal = calendar(timeZone)
        let start = cal.startOfDay(for: today)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: start)!
        var picks = [QuickPick(key: "today", title: "Today", date: start),
                     QuickPick(key: "tomorrow", title: "Tomorrow", date: tomorrow)]
        let weekday = cal.component(.weekday, from: start) // 1 = Sunday
        let daysToMonday = ((2 - weekday) + 7) % 7
        let monday = cal.date(byAdding: .day, value: daysToMonday == 0 ? 7 : daysToMonday, to: start)!
        if !picks.contains(where: { cal.isDate($0.date, inSameDayAs: monday) }) {
            picks.append(QuickPick(key: "monday", title: "Monday", date: monday))
        }
        return picks
    }

    /// Monday-first month grid padded to whole weeks; nil cells are padding.
    public static func monthCells(_ month: Date, timeZone: TimeZone = .current) -> [Date?] {
        let cal = calendar(timeZone)
        let comps = cal.dateComponents([.year, .month], from: month)
        let monthStart = cal.date(from: comps)!
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)!.count
        let startPadding = (cal.component(.weekday, from: monthStart) + 5) % 7
        let total = Int((Double(startPadding + daysInMonth) / 7).rounded(.up)) * 7
        return (0..<total).map { i in
            let dayNum = i - startPadding + 1
            guard dayNum >= 1, dayNum <= daysInMonth else { return nil }
            return cal.date(byAdding: .day, value: dayNum - 1, to: monthStart)
        }
    }

    /// The window a start day can be picked in: today through 30 days out.
    public static func rangeEnd(today: Date, timeZone: TimeZone = .current) -> Date {
        let cal = calendar(timeZone)
        return cal.date(byAdding: .day, value: 30, to: cal.startOfDay(for: today))!
    }
}

import Foundation

// The pure parts of pages/settings.tsx and pages/nutrition.tsx: what the profile save
// sends, which day labels the "Calendar colours" section lists, the "Renews" date and
// the nutrition page's calorie target. These live inline in the React components, so
// they are hand-ported (and hand-tested) rather than parity-generated.

public enum SettingsLogic {
    /// The PATCH /profile body the "Save changes" button sends.
    public struct ProfilePatch: Sendable, Equatable {
        public var name: String?
        public var weight: Double?
        public var weightUnit: String
        public var age: Int?
    }

    /// `{ name: name || undefined, weight: weight ? parseFloat(weight) : undefined,
    /// weightUnit, age: age ? parseInt(age) : undefined }`.
    ///
    /// Web quirks kept on purpose: a blank name is sent as "not set", so a name can't be
    /// cleared; validation reads the age with `Number()` but the save with `parseInt`, so
    /// "1e2" passes as 100 and is saved as 1; a non-number parse (NaN) is dropped here
    /// because NaN can't be serialised (JSON.stringify turns it into null).
    public static func profilePatch(name: String, age: String, weight: String, weightUnit: String) -> ProfilePatch {
        let w = weight.isEmpty ? nil : JS.parseFloat(weight)
        let a = age.isEmpty ? nil : JS.parseInt(age)
        return ProfilePatch(
            name: name.isEmpty ? nil : name,
            weight: w.flatMap { $0.isFinite ? $0 : nil },
            weightUnit: weightUnit,
            age: a.flatMap { $0.isFinite ? Int($0) : nil }
        )
    }

    /// The age/weight errors the page shows under the fields; Save is off while any is set.
    public static func profileErrors(age: String, weight: String) -> (age: String?, weight: String?) {
        (FieldLimits.rangeError(age, FieldLimits.age), FieldLimits.rangeError(weight, FieldLimits.weight))
    }

    /// A program as the colours section sees it.
    public struct ProgramLabels: Sendable, Equatable {
        public var aiGenerated: Bool
        public var labels: [String?]
        public init(aiGenerated: Bool, labels: [String?]) { self.aiGenerated = aiGenerated; self.labels = labels }
    }

    /// The days you can recolour: the current program's, in program order, then any
    /// stored label that some program in the active mode's lineage has a day for.
    /// Returns the labels in display order plus the colour-slot order for `dayColorHex`.
    public static func colorLabels(
        currentProgramLabels: [String?],
        programs: [ProgramLabels],
        storedLabels: [String],
        isIndependent: Bool
    ) -> (labels: [String], order: [String: Int]) {
        let lineageIsAi = !isIndependent
        var lineage = Set<String>()
        for program in programs where program.aiGenerated == lineageIsAi {
            for case let label? in program.labels where !label.isEmpty { lineage.insert(label) }
        }
        let stored: [String?] = storedLabels.filter { lineage.contains($0) }
        let order = DayColors.buildDayColorOrder(programLabels: currentProgramLabels, extraLabels: stored)
        // Object.keys(order): insertion order, which is the slot order.
        let labels = order.sorted { $0.value < $1.value }.map(\.key)
        return (labels, order)
    }

    /// `#rrggbb` (lowercase, like `<input type="color">`) from 0...1 channels.
    public static func hex(r: Double, g: Double, b: Double) -> String {
        func byte(_ v: Double) -> Int { Int((Swift.min(Swift.max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02lx%02lx%02lx", byte(r), byte(g), byte(b))
    }

    /// `new Date(currentPeriodEnd).toLocaleDateString("en-GB")`: "26/11/2026". Nil when
    /// the date doesn't parse (the web would print "Invalid Date").
    public static func renewsDate(_ raw: String, timeZone: TimeZone = .current) -> String? {
        guard let p = JSDate.localParts(JSDate.parse(raw, timeZone), timeZone) else { return nil }
        return String(format: "%02ld/%02ld/%ld", p.day, p.month0 + 1, p.year)
    }

    /// The nutrition page's target: Independent users set their own on the dashboard,
    /// the AI lineage's lives on the program. (The web reads the profile's mode while it
    /// is still loading as "not independent", so the program's target shows first.)
    public static func nutritionTarget(isIndependent: Bool, profileTarget: Int?, programTarget: Int?) -> Int? {
        isIndependent ? profileTarget : programTarget
    }

    /// "bulk" → "Bulk · Week 3", "mini_cut" → "Mini Cut" (CSS `capitalize` uppercases
    /// the first letter of each word).
    public static func phaseLine(shortTermPhase: String?, weekInPhase: Int?) -> String? {
        guard let phase = shortTermPhase, !phase.isEmpty else { return nil }
        let words = phase.replacingOccurrences(of: "_", with: " ").split(separator: " ", omittingEmptySubsequences: false)
        let capitalised = words.map { w in w.prefix(1).uppercased() + w.dropFirst() }.joined(separator: " ")
        return capitalised + (weekInPhase.map { " · Week \($0)" } ?? "")
    }
}

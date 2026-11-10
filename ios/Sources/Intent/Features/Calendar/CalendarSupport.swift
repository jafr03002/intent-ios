import Foundation
import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

// Colour and API-mapping helpers for the calendar. Feature-prefixed so they can't
// clash with another feature's helpers.

enum CalendarPaint {
    /// A day's `#rrggbb` (user pick or palette) as a Color.
    static func color(hex: String) -> Color {
        let c = DayColors.hexToRgb(hex)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    static func color(hsl: HSLColor) -> Color {
        let s = hsl.s / 100, l = hsl.l / 100
        let a = s * min(l, 1 - l)
        func channel(_ n: Double) -> Double {
            let k = (n + hsl.h / 30).truncatingRemainder(dividingBy: 12)
            return l - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return Color(.sRGB, red: channel(0), green: channel(8), blue: channel(4), opacity: 1)
    }

    /// The phase's hue, or the grey fallback (`phaseSolid`).
    static func phase(_ phase: String) -> Color {
        if let hue = PhaseColors.hue(phase) { return color(hsl: hue) }
        return color(hex: PhaseColors.fallbackHex)
    }

    static func chart(_ token: ChartToken) -> Color {
        switch token {
        case .chart1: Color.intent.chart1
        case .chart2: Color.intent.chart2
        case .chart3: Color.intent.chart3
        case .chart4: Color.intent.chart4
        case .chart5: Color.intent.chart5
        }
    }
}

enum CalendarAPIMapping {
    /// Generated schema -> IntentCore model through JSON: the field names are identical.
    static func convert<T: Decodable>(_ value: some Encodable, to type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            appLog.error("calendar: couldn't map \(String(describing: T.self), privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    static func phaseRow(_ p: IntentSchemas.Program) -> PhaseRow {
        let phase = p.shortTermPhase?.rawValue
        return PhaseRow(shortTermPhase: (phase?.isEmpty ?? true) ? nil : phase, weekInPhase: p.weekInPhase,
                        generatedAt: p.generatedAt, aiGenerated: p.aiGenerated, startDate: p.startDate)
    }

    static func schedule(_ s: IntentSchemas.ProgramSchedule?) -> ProgramSchedule? {
        guard let s, let mode = ScheduleMode(rawValue: s.mode.rawValue) else { return nil }
        return ProgramSchedule(mode: mode, slots: s.slots)
    }
}

/// A session the sheet is showing.
struct CalendarSessionItem: Identifiable, Equatable {
    let log: WorkoutLog
    var id: Int { log.id }
}

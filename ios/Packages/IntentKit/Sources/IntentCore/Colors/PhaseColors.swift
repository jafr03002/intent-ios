import Foundation

// Port of lib/phaseColors.ts as data: one fixed hue per short-term phase, shared by
// the calendar, dashboard and program page. IntentDesign turns these into Colors;
// the CSS strings are kept for parity checks and anything that wants the web's
// exact spelling.

public enum PhaseColors {
    public static let hues: [ShortTermPhase: HSLColor] = [
        .calibration: HSLColor(h: 199, s: 89, l: 48),
        .calibrationReview: HSLColor(h: 210, s: 70, l: 60),
        .bulk: HSLColor(h: 142, s: 71, l: 45),
        .maintenance: HSLColor(h: 38, s: 92, l: 50),
        .reverseDiet: HSLColor(h: 160, s: 84, l: 39),
        .diet: HSLColor(h: 350, s: 75, l: 55),
        .miniCut: HSLColor(h: 24, s: 90, l: 55),
        .deload: HSLColor(h: 217, s: 91, l: 60),
    ]

    /// Grey for a phase with no hue.
    public static let fallbackHex = "#6b7280"
    /// The soft wash's alpha.
    public static let softAlpha = 0.16

    public static func hue(_ phase: String) -> HSLColor? {
        ShortTermPhase(rawValue: phase).flatMap { hues[$0] }
    }

    /// "hsl(199, 89%, 48%)", or the grey fallback.
    public static func solid(_ phase: String) -> String {
        guard let c = hue(phase) else { return fallbackHex }
        return "hsl(\(JS.string(c.h)), \(JS.string(c.s))%, \(JS.string(c.l))%)"
    }

    /// "hsla(199, 89%, 48%, 0.16)", or the grey fallback at the same alpha.
    public static func soft(_ phase: String) -> String {
        guard let c = hue(phase) else { return "rgba(107, 114, 128, 0.16)" }
        return "hsla(\(JS.string(c.h)), \(JS.string(c.s))%, \(JS.string(c.l))%, 0.16)"
    }

    /// "reverse_diet" -> "reverse diet".
    public static func label(_ phase: String) -> String {
        phase.replacingOccurrences(of: "_", with: " ")
    }
}

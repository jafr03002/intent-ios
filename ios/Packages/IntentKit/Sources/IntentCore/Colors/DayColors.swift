import Foundation

// Port of lib/dayColors.ts as data: one colour per training day, shared by every
// surface that paints a day. The palette order is the calendar's original one (the
// only day colours ever persisted - Settings overrides key off them).

public struct RGB: Sendable, Equatable {
    /// 0...1 each.
    public var r: Double, g: Double, b: Double
}

/// Everything a surface needs from one day hex, as the web derives it.
public struct DayTones: Sendable, Equatable {
    /// The colour itself.
    public var solid: String
    /// Same hue at 0.14 alpha, for a wash.
    public var soft: String
    /// Lightened for text on `soft`.
    public var text: String
    /// Black-ish or white-ish foreground for text ON `solid` (WCAG luminance > 0.32).
    public var on: String
    /// Same hue at 0.35 alpha, for a glow.
    public var glow: String
    /// Bare "h s% l%" components.
    public var parts: String
    /// The hue as numbers, for IntentDesign.
    public var hsl: HSLColor
    /// Whether `on` is the dark foreground.
    public var onIsDark: Bool

    init(solid: String, soft: String, text: String, on: String, glow: String, parts: String, hsl: HSLColor, onIsDark: Bool) {
        self.solid = solid; self.soft = soft; self.text = text; self.on = on; self.glow = glow; self.parts = parts
        self.hsl = hsl; self.onIsDark = onIsDark
    }
}

public enum DayColors {
    public static let palette = [
        "#3b82f6", // blue
        "#10b981", // emerald
        "#f59e0b", // amber
        "#ef4444", // red
        "#8b5cf6", // violet
        "#06b6d4", // cyan
        "#ec4899", // pink
        "#84cc16", // lime
        "#f97316", // orange
        "#6366f1", // indigo
    ]

    public static let darkForeground = "hsl(224 47% 6%)"
    public static let lightForeground = "hsl(210 40% 98%)"

    /// A 3/6-digit hex as 0...1 channels; anything unparseable falls back to the
    /// first palette colour. (JS parseInt semantics: "#12345g" reads as 0x12345.)
    public static func hexToRgb(_ hex: String) -> RGB {
        var raw = JS.trim(hex)
        if let i = raw.firstIndex(of: "#") { raw.remove(at: i) }
        let units = Array(raw.utf16)
        let full = units.count == 3 ? String(decoding: units.flatMap { [$0, $0] }, as: UTF16.self) : raw
        let int = JS.parseInt(full, radix: 16)
        if full.utf16.count != 6 || int.isNaN { return RGB(r: 0.231, g: 0.51, b: 0.965) }
        let i = JS.toInt32(int)
        return RGB(r: Double((i >> 16) & 255) / 255, g: Double((i >> 8) & 255) / 255, b: Double(i & 255) / 255)
    }

    /// WCAG relative luminance.
    public static func luminance(_ hex: String) -> Double {
        let c = hexToRgb(hex)
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// Hue in whole degrees, saturation and lightness in whole percent (JS rounding).
    public static func hexToHsl(_ hex: String) -> HSLColor {
        let c = hexToRgb(hex)
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let l = (mx + mn) / 2
        if mx == mn { return HSLColor(h: 0, s: 0, l: JS.round(l * 100)) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        let h: Double
        if mx == c.r { h = ((c.g - c.b) / d + (c.g < c.b ? 6 : 0)) * 60 }
        else if mx == c.g { h = ((c.b - c.r) / d + 2) * 60 }
        else { h = ((c.r - c.g) / d + 4) * 60 }
        return HSLColor(h: JS.round(h), s: JS.round(s * 100), l: JS.round(l * 100))
    }

    public static func dayTones(_ hex: String) -> DayTones {
        let c = hexToHsl(hex)
        let h = JS.string(c.h), s = JS.string(c.s), l = JS.string(c.l)
        let dark = luminance(hex) > 0.32
        return DayTones(
            solid: hex,
            soft: "hsla(\(h), \(s)%, \(l)%, 0.14)",
            text: "hsl(\(h), \(JS.string(min(c.s, 80)))%, \(JS.string(max(c.l, 70)))%)",
            on: dark ? darkForeground : lightForeground,
            glow: "hsla(\(h), \(s)%, \(l)%, 0.35)",
            parts: "\(h) \(s)% \(l)%",
            hsl: c,
            onIsDark: dark
        )
    }

    /// Last-resort slot for a label no order knows (UTF-16 code units, like charCodeAt).
    static func labelHash(_ label: String) -> Int {
        var hash = 0
        for u in label.utf16 { hash = (hash * 31 + Int(u)) % 100_000 }
        return hash
    }

    /// The canonical colour slot per label: the program's days first, in order, then
    /// labels seen only in logged sessions. Blank labels and repeats are skipped.
    public static func buildDayColorOrder(programLabels: [String?], extraLabels: [String?] = []) -> [String: Int] {
        var order: [String: Int] = [:]
        var next = 0
        for label in programLabels + extraLabels {
            guard let label, !label.isEmpty, order[label] == nil else { continue }
            order[label] = next
            next += 1
        }
        return order
    }

    /// A user's own pick wins; else the label's slot (or its hash) into the palette.
    public static func dayColorHex(_ label: String, order: [String: Int] = [:], custom: [String: String] = [:]) -> String {
        if let picked = custom[label], !picked.isEmpty { return picked }
        return dayColorAt(order[label] ?? labelHash(label))
    }

    /// Colour by position. (The web returns undefined for a negative index; this wraps.)
    public static func dayColorAt(_ index: Int) -> String {
        palette[((index % palette.count) + palette.count) % palette.count]
    }
}

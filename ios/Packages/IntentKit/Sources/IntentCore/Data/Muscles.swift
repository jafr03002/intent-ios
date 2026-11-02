import Foundation

// Port of lib/muscles.ts: the 11 canonical muscle groups, in display order, and
// their chart colours as data (the design module turns them into Colors).

public enum Muscle: String, Codable, Sendable, CaseIterable {
    case chest = "Chest"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case upperBack = "Upper Back"
    case lats = "Lats"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case core = "Core"

    /// The label shown (and stored) everywhere - the web's MUSCLE_OPTIONS string.
    public var label: String { rawValue }

    /// The web's MUSCLE_COLORS entry.
    public var color: HSLColor {
        switch self {
        case .chest: HSLColor(h: 217, s: 91, l: 60)
        case .shoulders: HSLColor(h: 280, s: 68, l: 60)
        case .biceps: HSLColor(h: 38, s: 92, l: 50)
        case .triceps: HSLColor(h: 24, s: 90, l: 55)
        case .upperBack: HSLColor(h: 142, s: 71, l: 45)
        case .lats: HSLColor(h: 160, s: 84, l: 39)
        case .quads: HSLColor(h: 0, s: 72, l: 51)
        case .hamstrings: HSLColor(h: 350, s: 75, l: 55)
        case .glutes: HSLColor(h: 316, s: 73, l: 52)
        case .calves: HSLColor(h: 199, s: 89, l: 48)
        case .core: HSLColor(h: 90, s: 60, l: 45)
        }
    }
}

/// An HSL colour as data: hue in degrees, saturation and lightness in percent.
public struct HSLColor: Sendable, Equatable, Hashable, Codable {
    public var h: Double
    public var s: Double
    public var l: Double
    public init(h: Double, s: Double, l: Double) { self.h = h; self.s = s; self.l = l }

    /// CSS form, as the web writes it: "hsl(217, 91%, 60%)".
    public var css: String { "hsl(\(JS.string(h)), \(JS.string(s))%, \(JS.string(l))%)" }
}

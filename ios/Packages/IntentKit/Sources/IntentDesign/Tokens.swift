#if canImport(SwiftUI) // Apple-only module; compiles empty on Linux so `swift test` works in WSL
import SwiftUI

// Port of `appColors` in artifacts/traintent/src/theme/tokens.ts, kept 1:1: same
// names (kebab-case on the web, camelCase here) and the same HSL triples, so a
// change on one side is a copy-paste on the other.
//
// Sessions is almost monochrome: pure black, three neutral greys stepping up
// (background -> card -> secondary), white-on-black for primary and selected, and
// one teal accent (`sessionsCyan`). Note that `accent` is the hover grey, *not*
// the teal - that naming comes from shadcn.

/// Every colour token, named as on the web (`rawValue` is the CSS custom property
/// without `--`). Use `Color.intent.<name>` in views; this table is for tooling
/// and the styleguide.
public enum IntentColorToken: String, CaseIterable, Sendable {
    case background
    case foreground
    case border
    case card
    case cardForeground = "card-foreground"
    case cardBorder = "card-border"
    case sidebar
    case sidebarForeground = "sidebar-foreground"
    case sidebarBorder = "sidebar-border"
    case sidebarPrimary = "sidebar-primary"
    case sidebarPrimaryForeground = "sidebar-primary-foreground"
    case sidebarAccent = "sidebar-accent"
    case sidebarAccentForeground = "sidebar-accent-foreground"
    case sidebarRing = "sidebar-ring"
    case popover
    case popoverForeground = "popover-foreground"
    case popoverBorder = "popover-border"
    case primary
    case primaryForeground = "primary-foreground"
    case secondary
    case secondaryForeground = "secondary-foreground"
    case muted
    case mutedForeground = "muted-foreground"
    case accent
    case accentForeground = "accent-foreground"
    case destructive
    case destructiveForeground = "destructive-foreground"
    case input
    case ring
    case chart1 = "chart-1"
    case chart2 = "chart-2"
    case chart3 = "chart-3"
    case chart4 = "chart-4"
    case chart5 = "chart-5"
    case sessionsCyan = "sessions-cyan"

    /// The web value: "H S% L%".
    public var hsl: String {
        switch self {
        case .background: "0 0% 0%"
        case .foreground: "240 11% 96%"
        case .border: "240 4% 16%"
        case .card: "240 4% 9%"
        case .cardForeground: "240 11% 96%"
        case .cardBorder: "240 4% 16%"
        case .sidebar: "0 0% 0%"
        case .sidebarForeground: "240 11% 96%"
        case .sidebarBorder: "240 4% 16%"
        case .sidebarPrimary: "0 0% 100%"
        case .sidebarPrimaryForeground: "0 0% 0%"
        case .sidebarAccent: "240 4% 13%"
        case .sidebarAccentForeground: "240 11% 96%"
        case .sidebarRing: "0 0% 100%"
        case .popover: "240 4% 9%"
        case .popoverForeground: "240 11% 96%"
        case .popoverBorder: "240 4% 16%"
        case .primary: "0 0% 100%"
        case .primaryForeground: "0 0% 0%"
        case .secondary: "240 4% 13%"
        case .secondaryForeground: "240 11% 96%"
        case .muted: "240 4% 13%"
        case .mutedForeground: "240 2% 57%"
        case .accent: "240 4% 17%"
        case .accentForeground: "240 11% 96%"
        case .destructive: "0 72% 51%"
        case .destructiveForeground: "0 0% 98%"
        case .input: "240 4% 18%"
        case .ring: "0 0% 100%"
        case .chart1: "212 96% 62%"
        case .chart2: "158 82% 48%"
        case .chart3: "43 96% 60%"
        case .chart4: "250 90% 70%"
        case .chart5: "330 85% 62%"
        case .sessionsCyan: "187 83% 66%"
        }
    }

    /// The token as sRGB components (0...1), converted the same way as `hex()` on the web.
    public var rgb: (red: Double, green: Double, blue: Double) {
        let parts = hsl.split(separator: " ").map { Double($0.replacingOccurrences(of: "%", with: "")) ?? 0 }
        return Self.hslToRGB(h: parts[0], s: parts[1] / 100, l: parts[2] / 100)
    }

    /// `#rrggbb`, matching `hex(token)` in tokens.ts.
    public var hex: String {
        let (r, g, b) = rgb
        func byte(_ v: Double) -> String {
            let s = String(Int((v * 255).rounded()), radix: 16)
            return s.count == 1 ? "0" + s : s
        }
        return "#" + byte(r) + byte(g) + byte(b)
    }

    public var color: Color {
        let (r, g, b) = rgb
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    static func hslToRGB(h: Double, s: Double, l: Double) -> (red: Double, green: Double, blue: Double) {
        let a = s * min(l, 1 - l)
        func channel(_ n: Double) -> Double {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            return l - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return (channel(0), channel(8), channel(4))
    }
}

/// The palette as properties: `Color.intent.card`, `.foregroundStyle(.intent.mutedForeground)`.
public struct IntentPalette: Sendable {
    public let background = IntentColorToken.background.color
    public let foreground = IntentColorToken.foreground.color
    public let border = IntentColorToken.border.color
    public let card = IntentColorToken.card.color
    public let cardForeground = IntentColorToken.cardForeground.color
    public let cardBorder = IntentColorToken.cardBorder.color
    public let sidebar = IntentColorToken.sidebar.color
    public let sidebarForeground = IntentColorToken.sidebarForeground.color
    public let sidebarBorder = IntentColorToken.sidebarBorder.color
    public let sidebarPrimary = IntentColorToken.sidebarPrimary.color
    public let sidebarPrimaryForeground = IntentColorToken.sidebarPrimaryForeground.color
    public let sidebarAccent = IntentColorToken.sidebarAccent.color
    public let sidebarAccentForeground = IntentColorToken.sidebarAccentForeground.color
    public let sidebarRing = IntentColorToken.sidebarRing.color
    public let popover = IntentColorToken.popover.color
    public let popoverForeground = IntentColorToken.popoverForeground.color
    public let popoverBorder = IntentColorToken.popoverBorder.color
    public let primary = IntentColorToken.primary.color
    public let primaryForeground = IntentColorToken.primaryForeground.color
    public let secondary = IntentColorToken.secondary.color
    public let secondaryForeground = IntentColorToken.secondaryForeground.color
    public let muted = IntentColorToken.muted.color
    public let mutedForeground = IntentColorToken.mutedForeground.color
    public let accent = IntentColorToken.accent.color
    public let accentForeground = IntentColorToken.accentForeground.color
    public let destructive = IntentColorToken.destructive.color
    public let destructiveForeground = IntentColorToken.destructiveForeground.color
    public let input = IntentColorToken.input.color
    public let ring = IntentColorToken.ring.color
    public let chart1 = IntentColorToken.chart1.color
    public let chart2 = IntentColorToken.chart2.color
    public let chart3 = IntentColorToken.chart3.color
    public let chart4 = IntentColorToken.chart4.color
    public let chart5 = IntentColorToken.chart5.color
    /// The one accent (hero glass, AI badge, increases). Small doses only.
    public let sessionsCyan = IntentColorToken.sessionsCyan.color

    public subscript(token: IntentColorToken) -> Color { token.color }
}

private let sharedPalette = IntentPalette()

// Declared once, on `ShapeStyle where Self == Color`, so both `Color.intent.card`
// and `.foregroundStyle(.intent.card)` resolve without an ambiguity.
public extension ShapeStyle where Self == Color {
    static var intent: IntentPalette { sharedPalette }
}

// MARK: - Shape and spacing

/// Corner radii from TrainientAppDesign.md §4 and the web's `--radius` (0.75rem).
/// Everything uses continuous (squircle) corners.
public enum IntentRadius {
    /// `--radius`: 12.
    public static let base: CGFloat = 12
    /// `rounded-sm` / `rounded-md` / `rounded-lg` / `rounded-xl` off `--radius`.
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 12
    public static let xl: CGFloat = 16
    /// `rounded-3xl`: Sessions cards, option cards, inner bottom-sheet rows.
    public static let card: CGFloat = 24
    /// `rounded-[22px]`: notice / info cards.
    public static let notice: CGFloat = 22
    /// `rounded-[26px]`: inset grouped lists.
    public static let groupedList: CGFloat = 26
    /// `rounded-[30px]`: the hero card.
    public static let hero: CGFloat = 30
}

/// Spacing from the web (Tailwind's 4pt scale, as used by the Sessions screens).
public enum IntentSpacing {
    /// `p-6`: the page gutter.
    public static let gutter: CGFloat = 24
    /// `space-y-6`: between page sections.
    public static let section: CGFloat = 24
    /// `mb-3`: section title to its content.
    public static let sectionTitle: CGFloat = 12
    /// `gap-2.5`: between stacked option cards.
    public static let stack: CGFloat = 10
    /// `pl-5` / `px-5`: grouped-row and option-card text inset.
    public static let rowInset: CGFloat = 20
    /// `py-[15px]`: grouped-row vertical padding.
    public static let rowVertical: CGFloat = 15
    /// `py-[18px]`: option-card vertical padding.
    public static let optionVertical: CGFloat = 18
}

/// Fixed sizes.
public enum IntentMetrics {
    /// `border` / `border-b border-border`: 1 CSS px, which is 1pt on iPhone.
    public static let hairline: CGFloat = 1
    /// `h-[52px]`: pill buttons and pill inputs.
    public static let controlHeight: CGFloat = 52
    /// `h-[50px] w-[50px]`: round icon buttons.
    public static let iconButton: CGFloat = 50
    /// lucide `h-5 w-5` inside icon buttons.
    public static let iconSize: CGFloat = 20
    /// `h-16`: the tab bar row (without the home-indicator inset).
    public static let tabBarHeight: CGFloat = 64
    /// `h-14 w-14`: the raised Start disc.
    public static let startDisc: CGFloat = 56
}
#endif

#if canImport(SwiftUI) // Apple-only module; compiles empty on Linux so `swift test` works in WSL
import SwiftUI

// Inter only (TrainientAppDesign.md §3): the contrast comes from weight and size,
// not a second face. The web loads Inter 300-700 from Google Fonts; the same five
// static faces ship in Resources/Fonts (rsms/inter v4.1, SIL OFL 1.1).

/// The bundled Inter weights. Light (300) is for big display text only; body
/// text stays at 400-500 so it reads on black.
public enum IntentFontWeight: CaseIterable, Sendable {
    case light, regular, medium, semibold, bold

    public var postScriptName: String {
        switch self {
        case .light: "Inter-Light"
        case .regular: "Inter-Regular"
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        case .bold: "Inter-Bold"
        }
    }

    /// The CSS weight, for documentation and the styleguide.
    public var cssWeight: Int {
        switch self {
        case .light: 300
        case .regular: 400
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        }
    }
}

public extension Font {
    /// Inter at `size` points (1 CSS px = 1pt). Scales with Dynamic Type relative to
    /// `textStyle`, so the default size matches the web exactly.
    static func intent(_ size: CGFloat, _ weight: IntentFontWeight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom(weight.postScriptName, size: size, relativeTo: textStyle)
    }
}

/// The Sessions type scale. Apply with `.intentText(.screenTitle)`, which sets the
/// font, tracking, line spacing and caps in one go (colour stays the caller's).
public struct IntentTextStyle: Sendable {
    public let size: CGFloat
    public let weight: IntentFontWeight
    /// Letter spacing in em, as in the web classes (`tracking-[-0.025em]`).
    public let trackingEm: CGFloat
    /// CSS line-height multiple, or nil for Inter's natural leading.
    public let lineHeight: CGFloat?
    public let uppercase: Bool
    public let textStyle: Font.TextStyle

    public init(size: CGFloat, weight: IntentFontWeight, trackingEm: CGFloat = 0, lineHeight: CGFloat? = nil, uppercase: Bool = false, textStyle: Font.TextStyle = .body) {
        self.size = size
        self.weight = weight
        self.trackingEm = trackingEm
        self.lineHeight = lineHeight
        self.uppercase = uppercase
        self.textStyle = textStyle
    }

    public var font: Font { .intent(size, weight, relativeTo: textStyle) }
    public var tracking: CGFloat { trackingEm * size }

    /// Screen title: `text-[34px] font-light leading-[1.08] tracking-[-0.025em]` (PROGRAM_TITLE_CLASS).
    public static let screenTitle = IntentTextStyle(size: 34, weight: .light, trackingEm: -0.025, lineHeight: 1.08, textStyle: .largeTitle)
    /// Section title ("Training days"): `text-[21px] font-light tracking-[-0.01em]`.
    public static let sectionTitle = IntentTextStyle(size: 21, weight: .light, trackingEm: -0.01, textStyle: .title2)
    /// Hero title: `text-2xl font-normal tracking-[-0.01em]`.
    public static let heroTitle = IntentTextStyle(size: 24, weight: .regular, trackingEm: -0.01, textStyle: .title)
    /// Big stat number: `text-2xl font-light tracking-[-0.02em]`.
    public static let statNumber = IntentTextStyle(size: 24, weight: .light, trackingEm: -0.02, textStyle: .title)
    /// Stat-band input number on /log: `text-[26px] font-light`.
    public static let statInput = IntentTextStyle(size: 26, weight: .light, trackingEm: -0.02, textStyle: .title)
    /// Option-card title: `text-base font-medium`.
    public static let optionTitle = IntentTextStyle(size: 16, weight: .medium)
    /// Row title: `text-[15px] font-normal`.
    public static let rowTitle = IntentTextStyle(size: 15, weight: .regular)
    /// Trailing value on a grouped row: `text-[15px]` (muted).
    public static let rowValue = IntentTextStyle(size: 15, weight: .regular)
    /// Body: `text-sm leading-relaxed`.
    public static let body = IntentTextStyle(size: 14, weight: .regular, lineHeight: 1.625)
    /// Lede under a title: `text-[13.5px] leading-relaxed`.
    public static let lede = IntentTextStyle(size: 13.5, weight: .regular, lineHeight: 1.625, textStyle: .subheadline)
    /// Option-card subtitle: `text-[13px] leading-snug`.
    public static let optionSubtitle = IntentTextStyle(size: 13, weight: .regular, lineHeight: 1.375, textStyle: .subheadline)
    /// Row subtitle / notice copy: `text-[12.5px]`.
    public static let caption = IntentTextStyle(size: 12.5, weight: .regular, textStyle: .footnote)
    /// Caps label (stat labels, CTA): `text-[11px] uppercase tracking-[0.1em]`.
    public static let caps = IntentTextStyle(size: 11, weight: .regular, trackingEm: 0.1, uppercase: true, textStyle: .caption)
    /// Short eyebrow: `text-[11px] uppercase tracking-[0.14em]` (CAPS_CLASS).
    public static let eyebrow = IntentTextStyle(size: 11, weight: .regular, trackingEm: 0.14, uppercase: true, textStyle: .caption)
    /// Badge: `text-[10.5px] font-medium uppercase tracking-[0.1em]`.
    public static let badge = IntentTextStyle(size: 10.5, weight: .medium, trackingEm: 0.1, uppercase: true, textStyle: .caption2)
    /// Primary pill label: `text-sm font-semibold uppercase tracking-[0.06em]`.
    public static let button = IntentTextStyle(size: 14, weight: .semibold, trackingEm: 0.06, uppercase: true)
    /// Outlined pill label: `text-sm font-medium uppercase tracking-[0.06em]`.
    public static let buttonSecondary = IntentTextStyle(size: 14, weight: .medium, trackingEm: 0.06, uppercase: true)
    /// Pill / chip / segmented label: `text-sm`.
    public static let pill = IntentTextStyle(size: 14, weight: .regular)
    /// Tab-bar label: `text-[11px] font-medium`.
    public static let tabLabel = IntentTextStyle(size: 11, weight: .medium, textStyle: .caption2)
}

private struct IntentTextModifier: ViewModifier {
    let style: IntentTextStyle

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(lineSpacing)
            .textCase(style.uppercase ? .uppercase : nil)
    }

    /// CSS line-height minus Inter's natural leading (ascender + descender +
    /// line gap = 1.21em). Tighter-than-natural values (the 1.08 title) can't be
    /// expressed as negative line spacing, so they stay at natural leading.
    private var lineSpacing: CGFloat {
        guard let lineHeight = style.lineHeight else { return 0 }
        return max(0, (lineHeight - 1.21) * style.size)
    }
}

public extension View {
    /// Applies a Sessions type style: font, tracking, line spacing and caps.
    func intentText(_ style: IntentTextStyle) -> some View {
        modifier(IntentTextModifier(style: style))
    }
}
#endif

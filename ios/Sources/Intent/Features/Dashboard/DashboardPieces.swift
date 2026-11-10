import IntentCore
import IntentDesign
import SwiftUI

// Small Sessions pieces the dashboard uses (pages/dashboard.tsx, bottom of file).

// MARK: - Colour bridges (IntentCore data -> SwiftUI)

func dashboardColor(_ hsl: HSLColor, opacity: Double = 1) -> Color {
    let h = hsl.h, s = hsl.s / 100, l = hsl.l / 100
    let a = s * min(l, 1 - l)
    func channel(_ n: Double) -> Double {
        let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
        return l - a * max(-1, min(k - 3, 9 - k, 1))
    }
    return Color(.sRGB, red: channel(0), green: channel(8), blue: channel(4), opacity: opacity)
}

func dashboardColor(hex: String, opacity: Double = 1) -> Color {
    let c = DayColors.hexToRgb(hex)
    return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: opacity)
}

/// `phaseSolid(phase)`, grey for a phase with no hue.
func dashboardPhaseColor(_ phase: String, opacity: Double = 1) -> Color {
    if let hue = PhaseColors.hue(phase) { return dashboardColor(hue, opacity: opacity) }
    return dashboardColor(hex: PhaseColors.fallbackHex, opacity: opacity)
}

// MARK: - Wash

/// The grey-to-teal light behind the date arc and greeting, fading into black:
/// the web's live shader (DashboardWash.tsx) over the `.sessions-wash` gradient,
/// gathering over today's column. See LiveWash.
struct DashboardWash: View {
    var body: some View {
        LiveWash()
    }
}

// MARK: - Text bits

/// `DASHBOARD_TITLE_CLASS`.
struct DashboardTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .intentText(.screenTitle)
            .foregroundStyle(Color.intent.foreground)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The eyebrow over the name: `text-[11px] uppercase tracking-[0.14em] text-white/65`.
struct DashboardEyebrow: View {
    let text: String
    var body: some View {
        Text(text).intentText(.eyebrow).foregroundStyle(Color.white.opacity(0.65))
    }
}

/// Phase pill: `bg-secondary`, caps, the phase colour only in a 6pt dot.
struct DashboardPhasePill: View {
    let phase: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dashboardPhaseColor(phase)).frame(width: 6, height: 6)
            Text(PhaseColors.label(phase))
        }
        .intentText(.badge)
        .lineLimit(1)
        .foregroundStyle(Color.intent.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.intent.secondary))
        .fixedSize()
    }
}

// MARK: - Hero action row

/// `HERO_ACTION_CLASS`: the bottom-sheet row inside the hero card - a caps title and a
/// muted subtitle on the left, a white 52pt circle on the right.
struct DashboardHeroActionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.intent(12, .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.intent.foreground)
                Text(subtitle)
                    .intentText(.caption)
                    .foregroundStyle(Color.intent.mutedForeground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 52, height: 52)
                .background(Circle().fill(.white))
        }
        .padding(.vertical, 12)
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
    }
}

struct DashboardSurfaceButtonStyle: ButtonStyle {
    var fill: Color = Color.intent.secondary
    var pressed: Color = Color.intent.accent
    var radius: CGFloat = IntentRadius.card

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(configuration.isPressed ? pressed : fill))
    }
}

/// A small pill button (`h-9 rounded-full px-4 text-[12px] font-semibold uppercase`).
struct DashboardSmallPillStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.intent(12, .semibold))
            .tracking(0.72)
            .textCase(.uppercase)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .foregroundStyle(primary ? Color.intent.primaryForeground : Color.intent.foreground)
            .background(Capsule().fill(primary ? Color.white.opacity(configuration.isPressed ? 0.9 : 1)
                                               : (configuration.isPressed ? Color.intent.accent : Color.intent.secondary)))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Formatting

enum DashboardFormat {
    /// `toLocaleString()`: grouped in the device locale.
    static func grouped(_ n: Int) -> String { n.formatted(.number) }

    /// `toFixed(1)`.
    static func fixed1(_ x: Double) -> String { String(format: "%.1f", x) }

    /// A JS number as `${x}` prints it (78 not 78.0, 78.5).
    static func js(_ x: Double) -> String {
        x == x.rounded() && abs(x) < 1e15 ? String(Int(x)) : String(x)
    }

    /// date-fns `format(parseLocalDateString(s), pattern)` in English.
    static func date(_ s: String, _ pattern: String) -> String {
        guard let d = Calibration.parseLocalDateString(s) else { return s }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = pattern
        return f.string(from: d)
    }
}

import IntentCore
import IntentDesign
import SwiftUI

// Program-feature styling helpers. Candidates for IntentDesign once another feature
// needs them (the hero glass, the notice card, the field box).

extension Color {
    /// "#3b82f6" / "#abc" -> Color (DayColors' parser, so bad input falls back the same way).
    static func programHex(_ hex: String) -> Color {
        let c = DayColors.hexToRgb(hex)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    static func programHSL(_ c: HSLColor) -> Color {
        let s = c.s / 100, l = c.l / 100
        let a = s * min(l, 1 - l)
        func channel(_ n: Double) -> Double {
            let k = (n + c.h / 30).truncatingRemainder(dividingBy: 12)
            return l - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return Color(.sRGB, red: channel(0), green: channel(8), blue: channel(4), opacity: 1)
    }

    static func programChart(_ token: ChartToken) -> Color {
        switch token {
        case .chart1: Color.intent.chart1
        case .chart2: Color.intent.chart2
        case .chart3: Color.intent.chart3
        case .chart4: Color.intent.chart4
        case .chart5: Color.intent.chart5
        }
    }
}

/// `.sessions-glass`: the hero's grey-to-teal frosted gradient.
struct ProgramHeroGlass: View {
    var body: some View {
        // Each radial layer fills the whole hero (no offset frames, which left seams);
        // the end fractions approximate the CSS ellipse sizes.
        ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0x2b / 255, green: 0x2d / 255, blue: 0x30 / 255), location: 0),
                        .init(color: Color(red: 0x3c / 255, green: 0x43 / 255, blue: 0x47 / 255), location: 0.4),
                        .init(color: Color(red: 0x3c / 255, green: 0x75 / 255, blue: 0x84 / 255), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // radial-gradient(80% 90% at 55% 20%, rgb(210 220 225 / .28), transparent 65%)
                Rectangle().fill(EllipticalGradient(
                    colors: [Color(red: 210 / 255, green: 220 / 255, blue: 225 / 255).opacity(0.28), .clear],
                    center: UnitPoint(x: 0.55, y: 0.2), startRadiusFraction: 0, endRadiusFraction: 1.1
                ))
                // radial-gradient(90% 120% at 100% 100%, cyan / .55, transparent 60%)
                Rectangle().fill(EllipticalGradient(
                    colors: [Color.intent.sessionsCyan.opacity(0.55), .clear],
                    center: .bottomTrailing, startRadiusFraction: 0, endRadiusFraction: 1.15
                ))
        }
    }
}

/// `.sessions-watermark`: the faint diagonal "Train with intent" slogan.
struct ProgramHeroWatermark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<12, id: \.self) { _ in
                Text(String(repeating: "Train with intent · ", count: 8))
                    .font(.intent(15, .semibold))
                    .tracking(15 * 0.08)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: 15 * 1.9)
            }
        }
        .foregroundStyle(Color.white.opacity(0.07))
        .rotationEffect(.degrees(-16))
        .offset(x: -150, y: -60)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The notice card (`InactiveLineageNotice`): `rounded-[22px] bg-card`, a muted info
/// icon and 12.5pt muted copy.
struct ProgramNotice<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 1)
            content
                .font(.intent(12.5, .regular))
                .lineSpacing(4)
                .foregroundStyle(Color.intent.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .intentSurface(radius: IntentRadius.notice)
    }
}

/// A small label over a builder field ("Primary muscle worked").
struct ProgramFieldLabel: View {
    let text: String
    var centered = false
    var body: some View {
        Text(text)
            .font(.intent(11, .regular))
            .foregroundStyle(Color.intent.mutedForeground)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .lineLimit(1)
    }
}

extension View {
    /// The builder's input box: `bg-secondary`, rounded, red hairline when invalid.
    func programFieldBox(invalid: Bool = false, radius: CGFloat = IntentRadius.md) -> some View {
        self
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Color.intent.secondary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(invalid ? Color.intent.destructive : Color.clear, lineWidth: 1)
            )
    }
}

/// The empty / loading states' centred block.
struct ProgramCenteredMessage<Actions: View>: View {
    var systemImage: String? = "dumbbell"
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .padding(.bottom, 16)
            }
            Text(title)
                .font(.intent(24, .light))
                .tracking(-0.24)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.intent.foreground)
                .padding(.bottom, 8)
            Text(message)
                .intentText(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.bottom, 28)
            actions
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

/// The plain "Loading your program..." state.
struct ProgramLoading: View {
    var body: some View {
        Text("Loading your program...")
            .font(.intent(14, .regular))
            .foregroundStyle(Color.intent.mutedForeground)
            .frame(maxWidth: .infinity, minHeight: 256)
    }
}

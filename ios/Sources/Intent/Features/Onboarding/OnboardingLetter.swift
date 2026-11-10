import IntentDesign
import SwiftUI

// The "Coach's letter" kit (components/onboarding/letter.tsx) shared by the
// generating screen's successors: the presentation deck and the start-day screen.
// Each page opens with one sentence built from the client's data - facts white,
// the connecting words grey.

/// A piece of a letter sentence: `.fact` reads white, `.plain` grey.
enum OnboardingSayPart {
    case plain(String)
    case fact(String)
}

/// `Say`: light, tight tracking, grey with white facts.
struct OnboardingSay: View {
    let parts: [OnboardingSayPart]
    let size: CGFloat
    let lineHeight: CGFloat

    init(_ parts: [OnboardingSayPart], size: CGFloat, lineHeight: CGFloat) {
        self.parts = parts
        self.size = size
        self.lineHeight = lineHeight
    }

    var body: some View {
        parts.reduce(Text("")) { text, part in
            switch part {
            case .plain(let s): text + Text(s).foregroundStyle(Color.intent.mutedForeground)
            case .fact(let s): text + Text(s).foregroundStyle(Color.intent.foreground)
            }
        }
        .font(.intent(size, .light))
        .tracking(-0.02 * size)
        .lineSpacing(max(0, size * (lineHeight - 1.2)))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `PageHead`: a plain 34pt title with the letter sentence under it.
struct OnboardingPageHead: View {
    let title: String
    let parts: [OnboardingSayPart]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).onboardingTitle()
            OnboardingSay(parts, size: 20, lineHeight: 1.35)
        }
    }
}

/// `LetterWash`: the full storm wash bookends a flow; the pages between get the
/// colourless one. Pinned to the top, scrolls away with nothing (it's behind).
struct OnboardingLetterWash: View {
    let bookend: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h: CGFloat = bookend ? 560 : 440
            ZStack {
                if bookend {
                    LinearGradient(stops: [
                        .init(color: Color(red: 0x2f / 255, green: 0x35 / 255, blue: 0x38 / 255), location: 0),
                        .init(color: Color(red: 0x1b / 255, green: 0x22 / 255, blue: 0x24 / 255), location: 0.38),
                        .init(color: .black, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    EllipticalGradient(colors: [Color(red: 214 / 255, green: 222 / 255, blue: 222 / 255).opacity(0.22), .clear],
                                       center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: w * 1.5, height: h * 1.2)
                        .position(x: w / 2, y: h * 0.18)
                    EllipticalGradient(colors: [Color.intent.sessionsCyan.opacity(0.3), .clear],
                                       center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: w * 1.2, height: h * 1.1)
                        .position(x: w / 2, y: h * 0.3)
                } else {
                    LinearGradient(stops: [
                        .init(color: Color(red: 0x17 / 255, green: 0x18 / 255, blue: 0x1a / 255), location: 0),
                        .init(color: Color(red: 0x0b / 255, green: 0x0b / 255, blue: 0x0c / 255), location: 0.42),
                        .init(color: .black, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    EllipticalGradient(colors: [Color.white.opacity(0.07), .clear],
                                       center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: w * 1.2, height: h)
                        .position(x: w / 2, y: h * 0.22)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// `LetterDock`: one white pill in thumb reach, a round Back beside it when there
/// is somewhere to go back to, over a fade to black.
struct OnboardingLetterDock<Footer: View>: View {
    let label: String
    var disabled = false
    let onNext: () -> Void
    var onBack: (() -> Void)?
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .light))
                            .frame(width: 52, height: 52)
                            .foregroundStyle(Color.intent.foreground)
                            .background(Circle().fill(Color.intent.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                Button(label, action: onNext)
                    .buttonStyle(.intentPrimary)
                    .disabled(disabled)
            }
            footer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 8)
        .background(
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0.9), location: 0.5),
                .init(color: .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
    }
}

extension OnboardingLetterDock where Footer == EmptyView {
    init(label: String, disabled: Bool = false, onNext: @escaping () -> Void, onBack: (() -> Void)? = nil) {
        self.init(label: label, disabled: disabled, onNext: onNext, onBack: onBack, footer: { EmptyView() })
    }
}

/// `PageDots`: the current page is a 24pt white bar, the rest 6pt grey dots.
struct OnboardingPageDots: View {
    let count: Int
    let index: Int
    var onSelect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.white : Color.intent.secondary)
                    .frame(width: i == index ? 24 : 6, height: 6)
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture { onSelect?(i) }
                    .accessibilityLabel("Page \(i + 1)")
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
    }
}

/// The white Intent sun (the web's intent-sun.png; an SF Symbol stand-in until the
/// app bundles the asset).
struct OnboardingSun: View {
    let size: CGFloat
    var body: some View {
        IntentSunMark(size: size)
    }
}

/// The "Building your program" screen (GeneratingScreen.tsx): a turning disc with a
/// dumbbell and a status line that steps through six messages, 1.8 s apart, and
/// stays on the last.
struct OnboardingGeneratingView: View {
    static let messages = [
        "Laying out the schedule…", "Setting up workouts…", "Structuring your split…",
        "Balancing muscle groups…", "Dialing in sets and reps…", "Almost there…",
    ]
    @State private var index = 0
    @State private var turning = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "dumbbell")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Color.intent.foreground)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.intent.secondary))
                .rotationEffect(.degrees(turning ? 360 : 0))
                .animation(.linear(duration: 2.4).repeatForever(autoreverses: false), value: turning)
                .padding(.bottom, 32)
            Text("Building your program")
                .font(.intent(28, .light)).tracking(-0.56)
                .foregroundStyle(Color.intent.foreground)
                .padding(.bottom, 12)
            ZStack {
                Text(Self.messages[index])
                    .font(.intent(14))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .id(index)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                            removal: .opacity.combined(with: .offset(y: -8))))
            }
            .frame(height: 24)
            .animation(.easeOut(duration: 0.25), value: index)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.intent.background.ignoresSafeArea())
        .onAppear { turning = true }
        .task {
            while index < Self.messages.count - 1 {
                try? await Task.sleep(for: .milliseconds(1800))
                if Task.isCancelled { return }
                index += 1
            }
        }
    }
}

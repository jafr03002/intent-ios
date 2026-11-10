import IntentCore
import IntentDesign
import SwiftUI

/// Start while a session runs (components/layout.tsx): the raised disc holds a thick
/// filled dumbbell inside a thin teal arc that turns slowly, and the label is the
/// session's elapsed time in teal. Drawn as an overlay that lines up with
/// IntentTabBar's centre slot (same 5-column grid, height and type), because the
/// bar itself only knows the plain Start/Close states. The bar draws the disc and
/// the dumbbell (`startSystemImage: "dumbbell.fill"`, blank title); this adds the
/// arc and the clock and takes the tap (resume).
struct LiveStartDiscOverlay: View {
    let launcher: WorkoutLauncher
    let onResume: () -> Void

    var body: some View {
        if let active = launcher.active {
            HStack(alignment: .bottom, spacing: 0) {
                Color.clear.frame(maxWidth: .infinity)
                Color.clear.frame(maxWidth: .infinity)
                Button(action: onResume) {
                    VStack(spacing: 4) {
                        SpinningArc()
                            .frame(width: IntentMetrics.startDisc + 14, height: IntentMetrics.startDisc + 14)
                            .frame(width: IntentMetrics.startDisc, height: IntentMetrics.startDisc)
                            .padding(.top, -IntentMetrics.startDiscRise)
                        Text(label(active))
                            .intentText(.tabLabel)
                            .monospacedDigit()
                            .foregroundStyle(Color.intent.sessionsCyan)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: IntentMetrics.tabBarHeight)
                    // Same column as IntentTabBar's Start: the rise is tappable too.
                    .frame(height: IntentMetrics.tabBarHeight + IntentMetrics.startDiscRise, alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume your workout")
                Color.clear.frame(maxWidth: .infinity)
                Color.clear.frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: 448)
            .frame(height: IntentMetrics.tabBarHeight + IntentMetrics.startDiscRise)
            .frame(maxWidth: .infinity)
        }
    }

    private func label(_ active: ActiveSessionSummary) -> String {
        guard let started = active.startedAt else { return "Resume" }
        return SessionDuration.formatClock((launcher.now - started) / 1000)
    }
}

/// `border-2 border-sessions-cyan border-r-transparent animate-spin 3s`: a ring
/// with one quarter missing, turning once every three seconds.
private struct SpinningArc: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Color.intent.sessionsCyan, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 3).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
            .allowsHitTesting(false)
    }
}

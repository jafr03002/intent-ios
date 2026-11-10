import IntentCore
import IntentDesign
import SwiftUI

// components/workout/ChecklistItemCard.tsx + components/ChecklistLogCard.tsx: a
// checklist item in the logger, in program order among the lifts. A timed item
// that isn't done yet is the filling card with swipe-to-complete; everything else
// is a plain tick row.

extension ChartToken {
    /// The web's `hsl(var(--chart-N))`.
    var logColor: Color {
        switch self {
        case .chart1: Color.intent.chart1
        case .chart2: Color.intent.chart2
        case .chart3: Color.intent.chart3
        case .chart4: Color.intent.chart4
        case .chart5: Color.intent.chart5
        }
    }
}

struct ChecklistItemLogCard: View {
    let ex: DraftExercise
    let showTargets: Bool
    let now: Double
    let onCompleteRound: () -> Void
    let onToggleRound: () -> Void
    let onStart: () -> Void
    let onPause: () -> Void
    let onReset: () -> Void

    private var allDone: Bool { ex.completedRounds >= ex.targetRounds }
    private var timed: Bool { SessionTimers.isTimed(ex) }
    private var target: String? { showTargets ? ChecklistItems.describeTarget(ChecklistTarget(ex)) : nil }
    private var accent: Color { LogScreenRules.checklistAccent(ex).logColor }

    var body: some View {
        if timed && !allDone {
            TimedChecklistCard(
                name: ex.name, accent: accent, label: LogScreenRules.checklistLabel(ex),
                completedRounds: ex.completedRounds, targetRounds: ex.targetRounds,
                remaining: SessionTimers.remainingSeconds(ex, now: now), total: ex.targetSeconds ?? 0,
                isRunning: ex.timerEndsAt != nil, isPaused: ex.timerPausedRemaining != nil,
                onCompleteRound: onCompleteRound, onStart: onStart, onPause: onPause, onReset: onReset)
        } else {
            tickRow
        }
    }

    private var tickRow: some View {
        HStack(spacing: 12) {
            Button(action: onToggleRound) {
                ZStack {
                    Circle().fill(allDone ? Color.white : Color.intent.secondary)
                    if allDone {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                    } else if ex.completedRounds > 0 {
                        Text("\(ex.completedRounds)/\(ex.targetRounds)")
                            .font(.intent(11, .medium).monospacedDigit())
                            .foregroundStyle(Color.intent.mutedForeground)
                    }
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LogScreenRules.checklistTickLabel(ex))
            .accessibilityAddTraits(allDone ? .isSelected : [])

            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name)
                    .intentText(.rowTitle)
                    .strikethrough(allDone)
                    .foregroundStyle(allDone ? Color.intent.mutedForeground : Color.intent.foreground)
                    .lineLimit(1)
                subtitle
                    .font(.intent(12.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !timed, let target {
                Text(target).intentText(.rowValue).foregroundStyle(Color.intent.mutedForeground)
                    .lineLimit(1).fixedSize()
            }
        }
        .padding(.vertical, 14)
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .frame(maxWidth: .infinity)
        .background(Color.intent.card, in: RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous))
    }

    private var subtitle: Text {
        var out = Text(LogScreenRules.checklistLabel(ex)).font(.intent(12.5, .medium)).foregroundStyle(accent)
        if let round = LogScreenRules.roundLabel(completedRounds: ex.completedRounds, targetRounds: ex.targetRounds) {
            out = out + Text(" · \(round)").foregroundStyle(Color.intent.mutedForeground)
        }
        if let target, ex.targetRounds == 1 {
            out = out + Text(" · \(target)").foregroundStyle(Color.intent.mutedForeground)
        }
        return out
    }
}

/// The filling card: the card IS the progress bar (a surface step from card to
/// secondary sweeps across as the hold runs), and a horizontal swipe completes the
/// round. The swipe is never the only way: VoiceOver gets a "Complete" action.
struct TimedChecklistCard: View {
    let name: String
    let accent: Color
    let label: String
    let completedRounds: Int
    let targetRounds: Int
    let remaining: Int
    let total: Int
    let isRunning: Bool
    let isPaused: Bool
    let onCompleteRound: () -> Void
    let onStart: () -> Void
    let onPause: () -> Void
    let onReset: () -> Void

    @State private var dragFraction: Double?
    @State private var axis: Axis?
    @State private var cardWidth: CGFloat = 1

    private var roundLabel: String? { LogScreenRules.roundLabel(completedRounds: completedRounds, targetRounds: targetRounds) }
    private var committing: Bool { (dragFraction ?? 0) >= LogScreenRules.swipeCommitFraction }

    var body: some View {
        GeometryReader { geo in
            let fraction = dragFraction ?? LogScreenRules.timedFillFraction(remaining: remaining, total: total)
            Rectangle()
                .fill(Color.intent.secondary)
                .frame(width: geo.size.width * fraction)
                .animation(dragFraction == nil ? .linear(duration: 0.24) : nil, value: fraction)
        }
        .allowsHitTesting(false)
        .overlay(alignment: .topLeading) { content }
        .frame(height: 92)
        .background(Color.intent.card)
        .clipShape(RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
        .simultaneousGesture(swipe)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Complete \(roundLabel.map { "\($0) of " } ?? "")\(name)") { onCompleteRound() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button(action: { isRunning ? onPause() : onStart() }) {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .regular))
                        .offset(x: isRunning ? 0 : 1)
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRunning ? "Pause \(name)" : "Start \(name)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(name).intentText(.rowTitle).foregroundStyle(Color.intent.foreground).lineLimit(1)
                    (Text(label).font(.intent(12.5, .medium)).foregroundStyle(accent)
                     + Text(" · \(ChecklistItems.formatDuration(Double(total)))\(roundLabel.map { " · \($0)" } ?? "")")
                        .font(.intent(12.5)).foregroundStyle(Color.intent.mutedForeground))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isRunning || isPaused {
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(Color.intent.mutedForeground)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.intent.secondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset \(name)")
                }

                Text(ChecklistItems.formatDuration(Double(remaining)))
                    .font(.intent(26, .light).monospacedDigit())
                    .tracking(-0.52)
                    .foregroundStyle(Color.intent.foreground)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.top, 14)

            HStack(spacing: 2) {
                if committing {
                    Text("Release to complete").foregroundStyle(Color.intent.foreground)
                } else {
                    HStack(spacing: -5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .regular))
                        }
                    }
                    Text("Swipe to complete").padding(.leading, 4)
                }
            }
            .font(.intent(10.5))
            .tracking(1.05)
            .textCase(.uppercase)
            .foregroundStyle(Color.intent.mutedForeground.opacity(0.7))
            .padding(.leading, 68)
            .padding(.top, 6)
        }
    }

    /// Axis-locked: a vertical start leaves the scroll alone for the whole gesture.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: LogScreenRules.swipeAxisSlop)
            .onChanged { value in
                if axis == nil {
                    axis = abs(value.translation.height) >= abs(value.translation.width) ? .vertical : .horizontal
                }
                guard axis == .horizontal else { return }
                let width = max(1, cardWidth)
                dragFraction = min(1, max(0, value.translation.width / width))
            }
            .onEnded { _ in
                let commit = axis == .horizontal && committing
                axis = nil
                dragFraction = nil
                if commit { onCompleteRound() }
            }
    }
}

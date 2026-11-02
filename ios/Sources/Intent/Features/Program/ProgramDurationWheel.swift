import IntentCore
import IntentDesign
import SwiftUI

/// The minutes/seconds picker for a checklist item's duration (web
/// components/DurationWheel.tsx): two wheel columns, the value under the centre band
/// selected, 0...60 min and 0...59 s.
///
/// NOTE: the Log feature may build its own wheel in parallel; this one is
/// Program-local until the two are merged into IntentDesign.
struct ProgramDurationWheel: View {
    @Binding var seconds: Int
    var accent: Color = Color.programChart(.chart4)

    private var minutes: Binding<Int> {
        Binding(
            get: { min(seconds / 60, ChecklistItems.maxWheelMinutes) },
            set: { seconds = min($0 * 60 + seconds % 60, ChecklistItems.maxWheelSeconds) }
        )
    }

    private var secs: Binding<Int> {
        Binding(
            get: { seconds % 60 },
            set: { seconds = min((seconds / 60) * 60 + $0, ChecklistItems.maxWheelSeconds) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            column(minutes, range: 0...ChecklistItems.maxWheelMinutes, unit: "min", label: "Minutes")
            column(secs, range: 0...59, unit: "sec", label: "Seconds")
        }
        .frame(height: 96)
        .background(Color.intent.secondary, in: RoundedRectangle(cornerRadius: IntentRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: IntentRadius.md, style: .continuous)
                .strokeBorder(accent.opacity(seconds > 0 ? 0.5 : 0), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: IntentRadius.md, style: .continuous))
    }

    private func column(_ value: Binding<Int>, range: ClosedRange<Int>, unit: String, label: String) -> some View {
        Picker(label, selection: value) {
            ForEach(Array(range), id: \.self) { n in
                Text(unit == "sec" ? String(format: "%02d %@", n, unit) : "\(n) \(unit)")
                    .font(.intent(15, .regular))
                    .foregroundStyle(Color.intent.foreground)
                    .tag(n)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityLabel(label)
    }
}

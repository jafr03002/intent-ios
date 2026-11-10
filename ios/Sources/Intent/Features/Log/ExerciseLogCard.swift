import IntentCore
import IntentDesign
import SwiftUI

// components/workout/ExerciseCard.tsx + SetRow.tsx: a lift's card in the logger -
// header, the "stat band" set rows (big light boxless inputs split by hairlines),
// last session's note and this session's note.

struct ExerciseLogCard: View {
    let ex: DraftExercise
    let exIdx: Int
    let weightUnit: String
    let showTargets: Bool
    /// Independent mode hides the "how to" help: the program is the user's own.
    let showHelp: Bool
    /// AI mode's forward-looking targets (not Independent, not calibration, not a first-timer).
    let showProgressionTargets: Bool
    let calibration: Bool
    let prevSets: [LoggedSet]?
    let prevNote: LastNote?
    var focus: FocusState<LogFieldID?>.Binding
    let onUpdateSet: (Int, SetField, Double) -> Void
    let onToggleSet: (Int) -> Void
    let onUpdateNotes: (String) -> Void
    let onToggleNotes: () -> Void
    let onHelp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(ex.sets.enumerated()), id: \.element.setNumber) { setIdx, set in
                Group {
                    if calibration {
                        LogCalibrationSetRow(set: set, guide: LogScreenRules.calibrationGuide(ex)) { onToggleSet(setIdx) }
                    } else {
                        LogSetRow(
                            set: set, exIdx: exIdx, setIdx: setIdx, isUnilateral: ex.isUnilateral, weightUnit: weightUnit,
                            prevStr: SessionLogs.formatPrevSet(prevSets?[logAt: setIdx], weightUnit: weightUnit,
                                                               isUnilateral: ex.isUnilateral),
                            target: showProgressionTargets
                                ? TrainingTargets.targetFromPreviousSet(prevSets?[logAt: setIdx], name: ex.name,
                                                                        targetReps: ex.targetReps, weightUnit: weightUnit)
                                : nil,
                            focus: focus,
                            onChange: { field, value in onUpdateSet(setIdx, field, value) }
                        )
                    }
                }
                .id("set-\(exIdx)-\(setIdx)")
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.intent.card)
        .clipShape(RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(LogScreenRules.exerciseMeta(ex, showTargets: showTargets, calibration: calibration))
                    .intentText(.caps)
                    .foregroundStyle(Color.intent.mutedForeground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showHelp {
                    Button(action: onHelp) {
                        HStack(spacing: 5) {
                            Image(systemName: "questionmark.circle").font(.system(size: 11, weight: .light))
                            Text("How to").font(.intent(11.5))
                        }
                        .foregroundStyle(Color.intent.mutedForeground)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.intent.secondary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How to perform \(ex.name)")
                    .fixedSize()
                }
            }
            Text(ex.name)
                .font(.intent(22, .light))
                .tracking(-0.015 * 22)
                .foregroundStyle(Color.intent.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let prevNote {
                (Text(LogScreenRules.lastNotePrefix(prevNote)).foregroundStyle(Color.intent.mutedForeground.opacity(0.6))
                 + Text(prevNote.text).foregroundStyle(Color.intent.mutedForeground))
                    .font(.intent(11.5))
                    .lineSpacing(1)
                    .padding(.bottom, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onToggleNotes) {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble").font(.system(size: 12, weight: .light))
                    Text(LogScreenRules.notesButtonTitle(notes: ex.notes, hasPrevNote: prevNote != nil))
                        .font(.intent(12.5))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .light))
                        .rotationEffect(.degrees(ex.showNotes ? 180 : 0))
                }
                .foregroundStyle(ex.notes.isEmpty && !ex.showNotes ? Color.intent.mutedForeground : Color.intent.foreground)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(Color.intent.secondary))
            }
            .buttonStyle(.plain)
            if ex.showNotes {
                LogNotesField(text: ex.notes, placeholder: LogScreenRules.notesPlaceholder(calibration: calibration),
                              onChange: onUpdateNotes)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .overlay(alignment: .top) { IntentDivider() }
        .animation(.easeOut(duration: 0.18), value: ex.showNotes)
    }
}

/// The note textarea: `bg-secondary rounded-[20px]`, a hairline once focused.
struct LogNotesField: View {
    let text: String
    let placeholder: String
    var lines: ClosedRange<Int> = 2...6
    let onChange: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: Text(placeholder).foregroundStyle(Color.intent.mutedForeground.opacity(0.6)),
                  axis: .vertical)
            .lineLimit(lines)
            .font(.intent(13.5))
            .foregroundStyle(Color.intent.foreground)
            .focused($focused)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.intent.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(focused ? Color.intent.foreground.opacity(0.35) : .clear, lineWidth: 1))
            .onAppear { draft = text }
            .onChange(of: draft) { _, new in if new != text { onChange(new) } }
            .onChange(of: text) { _, new in if new != draft { draft = new } }
    }
}

// MARK: - Set rows

/// The faint cyan wash from the left on a logged (or PR) set, and its rail.
private struct LoggedRowBackground: View {
    let completed: Bool
    let isPr: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if isPr || completed {
                LinearGradient(
                    stops: [.init(color: Color.intent.sessionsCyan.opacity(isPr ? 0.06 : 0.045), location: 0),
                            .init(color: .clear, location: isPr ? 0.7 : 0.55)],
                    startPoint: .leading, endPoint: .trailing)
            }
            // The logged-set rail: consecutive logged rows join into one line.
            Rectangle()
                .fill(Color.intent.sessionsCyan)
                .frame(width: 2)
                .padding(.top, -1)
                .scaleEffect(x: 1, y: completed ? 1 : 0, anchor: .top)
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45), value: completed)
        }
        .animation(.easeOut(duration: 0.3), value: completed)
        .allowsHitTesting(false)
    }
}

/// The 52pt leading column: the set number over a caps "Set".
private struct SetNumberColumn: View {
    let number: Int
    let completed: Bool
    var isPr = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("\(number)")
                    .font(.intent(24, .light).monospacedDigit())
                    .foregroundStyle(completed ? Color.intent.foreground : Color.intent.mutedForeground)
                if isPr {
                    Image(systemName: "trophy")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Color.intent.sessionsCyan)
                        .transition(.scale)
                }
            }
            Text("Set").font(.intent(10)).tracking(1).textCase(.uppercase)
                .foregroundStyle(Color.intent.mutedForeground)
        }
        .frame(width: 52, alignment: .leading)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isPr)
    }
}

/// One set's stat band. Sets save implicitly as you type; no confirm step.
struct LogSetRow: View {
    let set: DraftSet
    let exIdx: Int
    let setIdx: Int
    let isUnilateral: Bool
    let weightUnit: String
    /// "Last time: 80 kg × 8"; nil hides it.
    let prevStr: String?
    /// AI mode's target; replaces the "last time" line when present.
    let target: SetTarget?
    var focus: FocusState<LogFieldID?>.Binding
    let onChange: (SetField, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                SetNumberColumn(number: set.setNumber, completed: set.completed, isPr: set.isNewPr)
                cell(weightUnit, field: .weight, value: set.weight, decimal: true)
                if isUnilateral {
                    cell("Reps L", field: .repsLeft, value: Double(set.repsLeft))
                    cell("Reps R", field: .repsRight, value: Double(set.repsRight))
                } else {
                    cell("Reps", field: .reps, value: Double(set.reps))
                }
            }
            hint
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(LoggedRowBackground(completed: set.completed, isPr: set.isNewPr))
        .overlay(alignment: .top) { IntentDivider() }
    }

    private func cell(_ label: String, field: SetField, value: Double, decimal: Bool = false) -> some View {
        let id = LogFieldID(exIdx: exIdx, setIdx: setIdx, field: field)
        return VStack(alignment: .leading, spacing: 1) {
            LogNumberField(value: value, decimal: decimal, id: id, focus: focus,
                           accessibilityLabel: accessibilityLabel(field)) { onChange(field, $0) }
            Text(label).font(.intent(10)).tracking(1).textCase(.uppercase)
                .foregroundStyle(Color.intent.mutedForeground)
                .lineLimit(1)
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { IntentDivider(.vertical) }
    }

    private func accessibilityLabel(_ field: SetField) -> String {
        switch field {
        case .weight: "Set \(set.setNumber) weight"
        case .reps: "Set \(set.setNumber) reps"
        case .repsLeft: "Set \(set.setNumber) reps, left"
        case .repsRight: "Set \(set.setNumber) reps, right"
        }
    }

    @ViewBuilder private var hint: some View {
        if let target {
            HStack(spacing: 6) {
                Text("Target").font(.intent(10.5)).tracking(0.84).textCase(.uppercase)
                    .foregroundStyle(Color.intent.mutedForeground)
                Text(LogScreenRules.targetText(target, weightUnit: weightUnit, isUnilateral: isUnilateral))
                    .font(.intent(10.5, .medium).monospacedDigit()).tracking(0.2)
                    .foregroundStyle(Color.intent.foreground)
                if set.isNewPr {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy").font(.system(size: 10, weight: .light))
                        Text("PR").font(.intent(10.5, .medium))
                    }
                    .foregroundStyle(Color.intent.sessionsCyan)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.intent.sessionsCyan.opacity(0.1)))
                } else {
                    Text(target.delta).font(.intent(10.5, .medium))
                        .foregroundStyle(Color.intent.foreground)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.intent.secondary))
                }
            }
            .lineLimit(1)
            .padding(.top, 8)
            .accessibilityHint(prevStr.map { "Last time: \($0)" } ?? "")
        } else if let prevStr {
            (Text("LAST TIME  ").font(.intent(10.5)).tracking(0.84).foregroundStyle(Color.intent.mutedForeground)
             + Text(prevStr).font(.intent(10.5, .medium)).tracking(0.2).foregroundStyle(Color.intent.foreground))
                .lineLimit(1)
                .padding(.top, 8)
        }
    }
}

/// A boxless number input: big light digits, a dim dash when empty, an underline
/// while focused. Keeps its own text so "82." survives typing; the model's value
/// wins whenever the two disagree (e.g. a clamp).
struct LogNumberField: View {
    let value: Double
    let decimal: Bool
    let id: LogFieldID
    var focus: FocusState<LogFieldID?>.Binding
    let accessibilityLabel: String
    let onChange: (Double) -> Void
    @State private var text = ""

    private func parse(_ s: String) -> Double {
        // `parseFloat(...) || 0` / `parseInt(...) || 0`; accept a decimal comma too.
        let normalized = s.replacingOccurrences(of: ",", with: ".")
        return decimal ? SetEditing.parseWeightInput(normalized) : SetEditing.parseRepsInput(normalized)
    }

    var body: some View {
        let focused = focus.wrappedValue == id
        TextField("", text: $text, prompt: Text("–").foregroundStyle(Color.intent.mutedForeground.opacity(0.4)))
            .font(.intent(26, .light).monospacedDigit())
            .tracking(-0.52)
            .foregroundStyle(Color.intent.foreground)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .focused(focus, equals: id)
            .padding(.bottom, 1)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? Color.intent.foreground.opacity(0.5) : .clear).frame(height: 1)
            }
            .accessibilityLabel(accessibilityLabel)
            .onAppear { text = LogScreenRules.inputText(value) }
            .onChange(of: text) { _, new in
                let parsed = parse(new)
                if parsed != value { onChange(parsed) }
            }
            .onChange(of: value) { _, new in
                if parse(text) != new { text = LogScreenRules.inputText(new) }
            }
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A calibration set: no numbers that week, just a tick. Same row, rail and number
/// as LogSetRow; the prescribed reps stay as a guide.
struct LogCalibrationSetRow: View {
    let set: DraftSet
    let guide: String
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SetNumberColumn(number: set.setNumber, completed: set.completed)
            (Text("GUIDE  ").font(.intent(10.5)).tracking(0.84).foregroundStyle(Color.intent.mutedForeground)
             + Text(guide).font(.intent(10.5, .medium)).tracking(0.2).foregroundStyle(Color.intent.foreground))
                .lineLimit(1)
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .overlay(alignment: .leading) { IntentDivider(.vertical) }
            Button(action: onToggle) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(set.completed ? Color.black : Color.clear)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(set.completed ? Color.white : Color.clear))
                    .overlay(Circle().strokeBorder(set.completed ? Color.white : Color.intent.mutedForeground.opacity(0.5),
                                                   lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(set.setNumber) \(set.completed ? "done" : "not done")")
            .accessibilityAddTraits(set.completed ? .isSelected : [])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(LoggedRowBackground(completed: set.completed, isPr: false))
        .overlay(alignment: .top) { IntentDivider() }
    }
}

import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// The manual program builder/editor (`ManualProgramBuilder`): program name, day
/// cards with lifts and checklist items, add/move/remove, the one-field-at-a-time save
/// gate, the muscle reminder, and a draft mirrored to UserDefaults while dirty.
struct ProgramBuilderView: View {
    @Environment(AppServices.self) private var services

    /// The program being edited; nil creates the (one) manual program.
    let editProgram: Program?
    let userId: String?
    var colorOverrides: [String: String] = [:]
    let onSaved: (Program) -> Void
    var onCancel: (() -> Void)?
    /// Debug: open the library sheet on the first exercise row.
    var debugOpenLibrary = false

    @State private var state: ProgramBuilderState
    @State private var saving = false
    @State private var saveError: String?
    @State private var showMuscleConfirm = false
    @State private var showCancelConfirm = false
    @FocusState private var focusedName: UUID?
    private let baseline: String

    init(editProgram: Program?, userId: String?, colorOverrides: [String: String] = [:],
         onSaved: @escaping (Program) -> Void, onCancel: (() -> Void)? = nil, debugOpenLibrary: Bool = false) {
        self.editProgram = editProgram
        self.userId = userId
        self.colorOverrides = colorOverrides
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.debugOpenLibrary = debugOpenLibrary
        let draft = userId.flatMap { ProgramDraftStore.load(userId: $0, programId: editProgram?.id) }
        _state = State(initialValue: ProgramBuilderState(draft: draft, editing: editProgram))
        baseline = ProgramBuilder.baselineBuilderState(programName: editProgram?.programName, days: editProgram?.days)
    }

    private var isDirty: Bool { state.serialized != baseline }

    var body: some View {
        VStack(alignment: .leading, spacing: IntentSpacing.section) {
            nameField
            ForEach(Array(state.days.enumerated()), id: \.element.id) { di, day in
                dayCard(di, day)
                    .id("builder-day-\(di)")
            }
            addDayButton
            if let error = state.fieldError {
                Text(error.message)
                    .font(.intent(14, .regular))
                    .foregroundStyle(Color.intent.destructive)
            }
            if let saveError {
                Text(saveError)
                    .font(.intent(14, .regular))
                    .foregroundStyle(Color.intent.destructive)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.intent.destructive.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: IntentRadius.notice, style: .continuous))
            }
            if showMuscleConfirm { muscleConfirm } else { saveRow }
        }
        .onChange(of: state.serialized) { _, _ in persistDraft() }
        .alert("Discard your changes?", isPresented: $showCancelConfirm) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard changes", role: .destructive) { discardEdits() }
        } message: {
            Text(editProgram != nil
                 ? "Your program stays exactly as it was saved - everything you changed here will be lost."
                 : "The program you've started building won't be saved.")
        }
    }

    // MARK: Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Program name")
                .font(.intent(14, .medium))
                .foregroundStyle(Color.intent.mutedForeground)
            TextField("", text: $state.programName,
                      prompt: Text("e.g. My PPL Program").foregroundStyle(Color.intent.mutedForeground))
                .font(.intent(15, .regular))
                .foregroundStyle(Color.intent.foreground)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .intentSurface(radius: IntentRadius.xl)
        }
    }

    private func dayCard(_ di: Int, _ day: ProgramEditDay) -> some View {
        let hex = colorOverrides[day.label.trimmingCharacters(in: .whitespaces)] ?? DayColors.dayColorAt(di)
        let tones = DayColors.dayTones(hex)
        let labelInvalid = state.fieldError?.field == .label && state.fieldError?.day == di
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Day \(di + 1)")
                    .font(.intent(12, .semibold))
                    .foregroundStyle(Color.programHSL(HSLColor(h: tones.hsl.h, s: min(tones.hsl.s, 80), l: max(tones.hsl.l, 70))))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.programHex(hex).opacity(0.14)))
                    .fixedSize()
                TextField("", text: Binding(get: { state.days[programSafe: di]?.label ?? "" },
                                            set: { state.setDayLabel(di, String($0.prefix(FieldLimits.maxDayLabel))) }),
                          prompt: Text("Day \(di + 1) name (e.g. Push, Upper A)").foregroundStyle(Color.intent.mutedForeground))
                    .font(.intent(14, .regular))
                    .foregroundStyle(Color.intent.foreground)
                    .programFieldBox(invalid: labelInvalid)
                    .frame(minWidth: 0, maxWidth: .infinity)
                if state.days.count > 1 {
                    HStack(spacing: 0) {
                        iconAction("arrow.up", "Move day up", disabled: di == 0) { state.moveDay(from: di, to: di - 1) }
                        iconAction("arrow.down", "Move day down", disabled: di == state.days.count - 1) {
                            state.moveDay(from: di, to: di + 1)
                        }
                        iconAction("trash", "Delete day", destructive: true) { state.removeDay(di) }
                    }
                    .fixedSize()
                }
            }

            VStack(spacing: 12) {
                ForEach(Array(day.exercises.enumerated()), id: \.element.id) { ei, ex in
                    if ex.kind == .checklist {
                        checklistRow(di, ei, ex, count: day.exercises.count)
                    } else {
                        liftRow(di, ei, ex, count: day.exercises.count)
                    }
                }
            }

            HStack(spacing: 20) {
                textAction("Add exercise") { state.addExercise(di) }
                textAction("Add checklist item") { state.addChecklistItem(di) }
            }
        }
        .padding(16)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            // The day's colour, as on the web builder (Settings overrides win).
            Rectangle().fill(Color.programHex(hex)).frame(width: 4)
        }
        .intentSurface(radius: IntentRadius.card)
        .clipShape(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous))
    }

    private func liftRow(_ di: Int, _ ei: Int, _ ex: ProgramEditExercise, count: Int) -> some View {
        let err = state.fieldError
        let nameInvalid = err?.field == .name && err?.day == di && err?.exercise == ei
        let setsInvalid = err?.field == .sets && err?.day == di && err?.exercise == ei
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                numberBadge(ei + 1, tint: Color.intent.mutedForeground, fill: Color.intent.accent)
                    .padding(.top, 10)
                ProgramExerciseNameField(
                    name: exerciseBinding(di, ei, \.name),
                    invalid: nameInvalid,
                    focus: $focusedName,
                    rowId: ex.id,
                    onPick: { picked in
                        // A library pick is a statement about the exercise: it overwrites
                        // the primary muscle; the secondary stays as the user set it.
                        state.patchExercise(di, ei) { $0.name = picked.name; $0.muscle = picked.muscle.label }
                    },
                    startsBrowsing: debugOpenLibrary && di == 0 && ei == 0
                )
                .frame(minWidth: 0, maxWidth: .infinity)
                rowActions(di, ei, count: count).padding(.top, 4)
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    ProgramFieldLabel(text: "Primary muscle worked")
                    musclePicker(exerciseBinding(di, ei, \.muscle), placeholder: "Select…")
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    ProgramFieldLabel(text: "Sets", centered: true)
                    numberField(exerciseBinding(di, ei, \.sets), placeholder: "Sets", invalid: setsInvalid)
                }
                .frame(width: 64)
                VStack(spacing: 4) {
                    ProgramFieldLabel(text: "Reps", centered: true)
                    TextField("", text: exerciseBinding(di, ei, \.reps),
                              prompt: Text("Reps").foregroundStyle(Color.intent.mutedForeground))
                        .font(.intent(14, .regular))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.intent.foreground)
                        .programFieldBox()
                }
                .frame(width: 72)
            }
            VStack(alignment: .leading, spacing: 4) {
                ProgramFieldLabel(text: "Secondary muscle worked (optional)")
                musclePicker(exerciseBinding(di, ei, \.secondaryMuscle), placeholder: "None", muted: true)
            }
            Button {
                state.patchExercise(di, ei) { $0.isUnilateral.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: ex.isUnilateral ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                    Text("Unilateral (one side at a time)")
                        .font(.intent(12, .regular))
                }
                .foregroundStyle(Color.intent.mutedForeground.opacity(ex.isUnilateral ? 1 : 0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.intent.secondary.opacity(ei % 2 == 0 ? 0.55 : 0.3),
                    in: RoundedRectangle(cornerRadius: IntentRadius.xl, style: .continuous))
    }

    private func checklistRow(_ di: Int, _ ei: Int, _ ex: ProgramEditExercise, count: Int) -> some View {
        let err = state.fieldError
        let nameInvalid = err?.field == .name && err?.day == di && err?.exercise == ei
        let setsInvalid = err?.field == .sets && err?.day == di && err?.exercise == ei
        let accent = Color.programChart(ChecklistItems.accent)
        let measured = ex.targetType == .count || ex.targetType == .distance
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                numberBadge(ei + 1, tint: accent, fill: accent.opacity(0.15))
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.1)))
                    .accessibilityLabel("Checklist item")
                TextField("", text: exerciseBinding(di, ei, \.name, limit: FieldLimits.maxExerciseName),
                          prompt: Text("e.g. Couch stretch").foregroundStyle(Color.intent.mutedForeground))
                    .font(.intent(14, .regular))
                    .foregroundStyle(Color.intent.foreground)
                    .programFieldBox(invalid: nameInvalid)
                    .frame(minWidth: 0, maxWidth: .infinity)
                rowActions(di, ei, count: count)
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    ProgramFieldLabel(text: "Track by")
                    Menu {
                        Picker("Track by", selection: Binding(get: { ex.targetType },
                                                              set: { state.setTargetType(di, ei, $0) })) {
                            ForEach(ChecklistItems.targetTypeOptions, id: \.value) { o in
                                Text(o.label).tag(o.value)
                            }
                        }
                    } label: {
                        menuLabel(ChecklistItems.targetTypeOptions.first { $0.value == ex.targetType }?.label ?? "")
                    }
                    if ex.targetType == .duration {
                        ProgramDurationWheel(seconds: exerciseBinding(di, ei, \.durationSeconds), accent: accent)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                if measured {
                    VStack(spacing: 4) {
                        ProgramFieldLabel(text: "Amount", centered: true)
                        TextField("", text: Binding(
                            get: { ex.targetValue },
                            set: { v in state.patchExercise(di, ei) { $0.targetValue = v.filter { $0.isNumber || $0 == "." } } }
                        ), prompt: Text(ex.targetType == .count ? "20" : "400").foregroundStyle(Color.intent.mutedForeground))
                            .keyboardType(.decimalPad)
                            .font(.intent(14, .regular))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.intent.foreground)
                            .programFieldBox()
                    }
                    .frame(width: 64)
                }
                if ex.targetType == .distance {
                    VStack(spacing: 4) {
                        ProgramFieldLabel(text: "Unit", centered: true)
                        Menu {
                            Picker("Unit", selection: exerciseBinding(di, ei, \.targetUnit)) {
                                ForEach(ChecklistItems.distanceUnits, id: \.self) { Text($0).tag($0) }
                            }
                        } label: { menuLabel(ex.targetUnit, centered: true) }
                    }
                    .frame(width: 60)
                }
                VStack(spacing: 4) {
                    ProgramFieldLabel(text: "Rounds", centered: true)
                    numberField(exerciseBinding(di, ei, \.sets), placeholder: "1", invalid: setsInvalid)
                }
                .frame(width: measured ? 60 : 96)
            }
            VStack(alignment: .leading, spacing: 4) {
                ProgramFieldLabel(text: "Category (optional)")
                Menu {
                    Picker("Category", selection: exerciseBinding(di, ei, \.category)) {
                        Text("None").tag("")
                        ForEach(ChecklistItems.categories, id: \.value) { c in Text(c.label).tag(c.value.rawValue) }
                    }
                } label: {
                    menuLabel(ChecklistItems.categoryMeta(ex.category)?.label ?? "None", muted: ex.category.isEmpty)
                }
            }
            if ex.targetType == .duration && ex.durationSeconds > 0 {
                Label("Shows a \(ChecklistItems.formatDuration(Double(ex.durationSeconds))) timer when logging",
                      systemImage: "timer")
                    .font(.intent(11, .semibold))
                    .foregroundStyle(accent)
            }
        }
        .padding(10)
        .background(Color.intent.secondary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: IntentRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: IntentRadius.xl, style: .continuous)
                .strokeBorder(accent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: Small parts

    private func exerciseBinding<T>(_ di: Int, _ ei: Int, _ key: WritableKeyPath<ProgramEditExercise, T>,
                                    limit: Int? = nil) -> Binding<T> {
        Binding(
            get: { state.days[programSafe: di]?.exercises[programSafe: ei]?[keyPath: key] ?? ProgramBuilder.newExercise()[keyPath: key] },
            set: { value in
                state.patchExercise(di, ei) { ex in
                    if let limit, let s = value as? String, s.count > limit, let cut = String(s.prefix(limit)) as? T {
                        ex[keyPath: key] = cut
                    } else {
                        ex[keyPath: key] = value
                    }
                }
            }
        )
    }

    private func numberBadge(_ n: Int, tint: Color, fill: Color) -> some View {
        Text("\(n)")
            .font(.intent(11, .medium))
            .foregroundStyle(tint)
            .frame(width: 20, height: 20)
            .background(Circle().fill(fill))
    }

    private func rowActions(_ di: Int, _ ei: Int, count: Int) -> some View {
        HStack(spacing: 0) {
            iconAction("arrow.up", "Move up", disabled: ei == 0, small: true) { state.moveExercise(di, ei, by: -1) }
            iconAction("arrow.down", "Move down", disabled: ei == count - 1, small: true) { state.moveExercise(di, ei, by: 1) }
            iconAction("trash", "Remove", destructive: true, small: true) { state.removeExercise(di, ei) }
        }
        .fixedSize()
    }

    private func iconAction(_ systemImage: String, _ label: String, disabled: Bool = false, destructive: Bool = false,
                            small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: small ? 13 : 15, weight: .light))
                .foregroundStyle(Color.intent.mutedForeground)
                .frame(width: small ? 28 : 34, height: small ? 30 : 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(label)
    }

    private func textAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.intent(12.5, .regular))
                .foregroundStyle(Color.intent.mutedForeground)
        }
        .buttonStyle(.plain)
    }

    private func menuLabel(_ text: String, centered: Bool = false, muted: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.intent(14, .regular))
                .foregroundStyle(muted ? Color.intent.mutedForeground : Color.intent.foreground)
                .lineLimit(1)
            if !centered { Spacer(minLength: 4) }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(Color.intent.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .programFieldBox()
    }

    private func musclePicker(_ selection: Binding<String>, placeholder: String, muted: Bool = false) -> some View {
        Menu {
            Picker(placeholder, selection: selection) {
                Text(placeholder).tag("")
                ForEach(Muscle.allCases, id: \.self) { m in Text(m.label).tag(m.label) }
            }
        } label: {
            menuLabel(selection.wrappedValue.isEmpty ? placeholder : selection.wrappedValue,
                      muted: muted || selection.wrappedValue.isEmpty)
        }
    }

    private func numberField(_ text: Binding<String>, placeholder: String, invalid: Bool) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.intent.mutedForeground))
            .keyboardType(.numberPad)
            .font(.intent(14, .regular))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.intent.foreground)
            .programFieldBox(invalid: invalid)
    }

    private var addDayButton: some View {
        Button { state.addDay() } label: {
            Label("Add training day", systemImage: "plus")
                .font(.intent(14, .regular))
                .foregroundStyle(Color.intent.mutedForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: IntentRadius.xl, style: .continuous)
                        .strokeBorder(Color.intent.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var saveRow: some View {
        HStack(spacing: 8) {
            if onCancel != nil {
                Button("Cancel", action: handleCancel)
                    .buttonStyle(.intentOutline)
                    .frame(width: 120)
                    .accessibilityIdentifier("button-cancel-builder")
            }
            Button(action: handleSave) {
                if saving {
                    HStack(spacing: 8) { ProgressView().tint(.black); Text("Saving...") }
                } else {
                    Text(editProgram != nil ? "Save changes" : "Save program")
                }
            }
            .buttonStyle(.intentPrimary)
            .disabled(saving)
        }
    }

    private var muscleConfirm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Some exercises don't have a muscle group set. You can save without it, but they won't show up in your muscle-volume breakdown.")
                .font(.intent(14, .regular))
                .foregroundStyle(Color.intent.foreground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Go back") { showMuscleConfirm = false }
                    .buttonStyle(.intentOutline)
                    .frame(width: 120)
                Button {
                    Task { await performSave() }
                } label: {
                    Text(saving ? "Saving..." : "Save anyway")
                }
                .buttonStyle(.intentPrimary)
                .disabled(saving)
            }
        }
        .padding(16)
        .intentSurface(radius: IntentRadius.notice)
    }

    // MARK: Actions

    private func persistDraft() {
        guard let userId else { return }
        if isDirty {
            ProgramDraftStore.save(userId: userId, programId: editProgram?.id, programName: state.programName, days: state.days)
        } else {
            ProgramDraftStore.clear(userId: userId, programId: editProgram?.id)
        }
    }

    private func handleSave() {
        guard state.validateForSave() else { return }
        if ProgramBuilder.hasUnsetMuscle(state.days) {
            showMuscleConfirm = true
            return
        }
        Task { await performSave() }
    }

    private func performSave() async {
        saving = true
        saveError = nil
        defer {
            saving = false
            showMuscleConfirm = false
        }
        do {
            let input = try ProgramAPI.manualInput(
                name: ProgramBuilder.saveName(state.programName),
                splitType: ProgramBuilder.saveSplitType(editProgram?.splitType),
                days: ProgramBuilder.programDays(state.days)
            )
            let saved: Program
            if let editProgram {
                saved = try await ProgramAPI.updateProgram(services, id: editProgram.id, input)
            } else {
                saved = try await ProgramAPI.createManualProgram(services.api, input)
            }
            if let userId { ProgramDraftStore.clear(userId: userId, programId: editProgram?.id) }
            onSaved(saved)
        } catch {
            // The draft stays: the work isn't saved.
            saveError = "Couldn't save your program: \(error.localizedDescription)"
        }
    }

    private func discardEdits() {
        if let userId { ProgramDraftStore.clear(userId: userId, programId: editProgram?.id) }
        showCancelConfirm = false
        onCancel?()
    }

    private func handleCancel() {
        if isDirty { showCancelConfirm = true } else { discardEdits() }
    }
}

fileprivate extension Array {
    subscript(programSafe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

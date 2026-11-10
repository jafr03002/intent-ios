import IntentCore
import IntentDesign
import SwiftUI

/// The session sheet (calendar.tsx `SessionModal`): the logged workout in full -
/// exercises with per-set progression against the previous session, PR rows, notes,
/// checklist items - and "Delete session" behind a confirm.
struct CalendarSessionSheet: View {
    let session: WorkoutLog
    let allWorkouts: [WorkoutLog]
    let color: Color
    let onDelete: () async throws -> Void
    let onClose: () -> Void
    /// Debug: open the delete confirm straight away.
    var startWithDeleteConfirm = false

    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var deleteFailed = false

    private var isCalibration: Bool { session.loggingMode == .calibration }

    var body: some View {
        VStack(spacing: 0) {
            header
            IntentDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(session.exercisesLogged.enumerated()), id: \.offset) { _, ex in
                        if ex.kind == .checklist {
                            checklistRow(ex)
                        } else {
                            exerciseBlock(ex)
                        }
                    }
                    if let notes = session.notes, !notes.isEmpty {
                        noteCard(notes)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        IntentDivider()
                        Button { showDeleteConfirm = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash").font(.system(size: 14, weight: .light))
                                Text("Delete session").font(.intent(14))
                            }
                            .foregroundStyle(Color.intent.destructive)
                            .padding(.vertical, 8)
                            .padding(.top, 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("delete-session-button")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.intent.card.ignoresSafeArea())
        .foregroundStyle(Color.intent.foreground)
        .sheet(isPresented: $showDeleteConfirm) { deleteConfirm }
        .task {
            guard startWithDeleteConfirm else { return }
            try? await Task.sleep(for: .milliseconds(700))
            showDeleteConfirm = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(session.dayLabel ?? "Workout")
                        .intentText(.sectionTitle)
                        .lineLimit(1)
                }
                (Text(CalendarMonth.longDate(session.date))
                    + Text(" · \(CalendarMonth.modeLabel(session))").foregroundColor(Color.intent.mutedForeground.opacity(0.6)))
                    .font(.intent(12.5))
                    .foregroundStyle(Color.intent.mutedForeground)
                if let duration = session.durationSeconds {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock").font(.system(size: 12, weight: .light))
                            if let started = session.startedAt, !started.isEmpty {
                                Text(SessionDuration.formatStartTime(started))
                                Text("·").foregroundStyle(Color.intent.mutedForeground.opacity(0.6))
                            }
                            Text(SessionDuration.formatSessionLength(Double(duration)))
                        }
                        .font(.intent(12.5))
                        .foregroundStyle(Color.intent.mutedForeground)
                        if !SessionDuration.countsTowardAverage(session) {
                            Text("Not counted toward your average")
                                .font(.intent(11))
                                .foregroundStyle(Color.intent.mutedForeground.opacity(0.7))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .light))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.intent.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close session")
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: Rows

    private func checklistRow(_ ex: LoggedExercise) -> some View {
        let meta = ChecklistItems.categoryMeta(ex.category)
        let accent = CalendarPaint.chart(meta?.token ?? ChecklistItems.accent)
        let done = (ex.completedRounds ?? 0) > 0
        return HStack(spacing: 12) {
            Image(systemName: done ? "checkmark" : "checklist")
                .font(.system(size: 14, weight: done ? .semibold : .light))
                .foregroundStyle(done ? Color.intent.chart2 : Color.intent.mutedForeground.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.intent.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.intent(15)).lineLimit(1).opacity(done ? 1 : 0.6)
                HStack(spacing: 0) {
                    Text(meta?.label ?? "Checklist").foregroundStyle(accent)
                    if let target = ex.targetSeconds, target > 0 {
                        Text(" · \(ChecklistItems.formatDuration(Double(target)))")
                    }
                    if let rounds = ex.completedRounds, rounds > 1 {
                        Text(" · \(rounds) rounds")
                    }
                }
                .font(.intent(12.5))
                .foregroundStyle(Color.intent.mutedForeground)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exerciseBlock(_ ex: LoggedExercise) -> some View {
        let prevSets = CalendarMonth.previousSets(for: ex.name, before: session, in: allWorkouts)
        let realSets = ex.sets.filter { !SessionLogs.isEmptySet($0) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IntentBadge(ex.muscle)
                if prevSets == nil && !isCalibration {
                    Text("First time logging this exercise")
                        .font(.intent(11))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .lineLimit(1)
                }
            }
            Text(ex.name).font(.intent(17)).padding(.top, 8)
            if isCalibration {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    Text("\(ex.sets.filter(\.completed).count) of \(ex.sets.count) sets done")
                }
                .font(.intent(12.5))
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 4)
            }
            if !realSets.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(realSets.enumerated()), id: \.offset) { i, s in
                        setRow(s, previous: prevSets, last: i == realSets.count - 1)
                    }
                }
                .background(Color.intent.secondary.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 8)
            }
            if let notes = ex.notes, !notes.isEmpty {
                noteCard(notes).padding(.top, 8)
            }
        }
    }

    private func setRow(_ s: LoggedSet, previous: [LoggedSet]?, last: Bool) -> some View {
        let delta = CalendarMonth.setDelta(s, previous: previous)
        return HStack(spacing: 12) {
            Text("Set \(s.setNumber)")
                .font(.intent(10.5))
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(Color.intent.mutedForeground)
                .frame(width: 44, alignment: .leading)
            Text(CalendarMonth.setLabel(s))
                .font(.intent(14))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            if s.isNewPr == true {
                HStack(spacing: 4) {
                    Image(systemName: "trophy").font(.system(size: 11, weight: .light))
                    Text("PR").intentText(.badge)
                }
                .foregroundStyle(Color.intent.sessionsCyan)
            }
            Spacer(minLength: 0)
            if let delta {
                HStack(spacing: 8) {
                    Text(CalendarMonth.deltaText(delta.weight, unit: "kg")).foregroundStyle(deltaColor(delta.weight))
                    Text(CalendarMonth.deltaText(Double(delta.reps), unit: delta.reps == 0 ? "" : " reps"))
                        .foregroundStyle(deltaColor(Double(delta.reps)))
                }
                .font(.intent(12))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.vertical, 10)
        .padding(.trailing, 16)
        .overlay(alignment: .bottom) { if !last { IntentDivider() } }
        .padding(.leading, 16)
        .background {
            if s.isNewPr == true {
                LinearGradient(stops: [.init(color: Color.intent.sessionsCyan.opacity(0.14), location: 0),
                                       .init(color: .clear, location: 0.7)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
    }

    /// Cyan for increases only; a drop is plain muted text.
    private func deltaColor(_ d: Double) -> Color {
        d > 0 ? Color.intent.sessionsCyan : d < 0 ? Color.intent.mutedForeground : Color.intent.mutedForeground.opacity(0.6)
    }

    private func noteCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 1)
            Text(text)
                .intentText(.caption)
                .lineSpacing(4)
                .foregroundStyle(Color.intent.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.intent.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Delete

    private var deleteConfirm: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Delete this session?").intentText(.sectionTitle)
                Text("All PRs and data from this session will be deleted. This can't be undone.")
                    .intentText(.caption)
                    .lineSpacing(4)
                    .foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if deleteFailed {
                Text("Something went wrong. Please try again.")
                    .font(.intent(14))
                    .foregroundStyle(Color.intent.destructive)
            }
            HStack(spacing: 8) {
                Button("Cancel") { showDeleteConfirm = false }
                    .buttonStyle(.intentOutline)
                Button {
                    Task { await runDelete() }
                } label: {
                    Text(deleting ? "Deleting…" : "Delete").foregroundStyle(Color.intent.destructive)
                }
                .buttonStyle(.intentSecondary)
                .accessibilityIdentifier("confirm-delete-session")
            }
            .disabled(deleting)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.intent.foreground)
        .presentationDetents([.height(220)])
        .presentationBackground(Color.intent.card)
        .presentationCornerRadius(30)
        .interactiveDismissDisabled(deleting)
    }

    private func runDelete() async {
        deleting = true
        deleteFailed = false
        do {
            try await onDelete()
            deleting = false
            showDeleteConfirm = false
            onClose()
        } catch {
            deleting = false
            deleteFailed = true
        }
    }
}

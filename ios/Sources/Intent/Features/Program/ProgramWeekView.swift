import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// The read-only program view (`ProgramWeekView`, the Sessions reference screen):
/// header, the day hero with Start workout, the day pills and the inset grouped roster.
/// The week strip (`ScheduleStrip`) is parked on the web, so it isn't here either.
struct ProgramWeekView: View {
    @Environment(AppServices.self) private var services

    let program: Program
    /// Only the active mode's lineage can start a workout.
    let canStartWorkout: Bool
    let badge: IntentBadge
    var durationStats: [DayDurationStat] = []
    var onEdit: (() -> Void)?
    /// Called after the start date was moved to today from the lock dialog.
    var onProgramChanged: (() -> Void)?
    var initialDay = 0

    @State private var activeDay = 0
    @State private var showLock = false
    @State private var lockFailed = false
    @State private var openLog = false
    @Environment(WorkoutLauncher.self) private var launcher: WorkoutLauncher?
    @State private var openProgress = false
    @State private var didSetInitialDay = false

    private var days: [ProgramDay] { program.days }
    private var day: ProgramDay? { days.indices.contains(activeDay) ? days[activeDay] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: IntentSpacing.section) {
            header
            if let day {
                hero(day)
                    .id("hero-\(activeDay)")
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            VStack(alignment: .leading, spacing: IntentSpacing.section) {
                dayTabs
                if let day, !day.exercises.isEmpty {
                    roster(day).id("program-roster")
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: activeDay)
        .onAppear {
            guard !didSetInitialDay else { return }
            didSetInitialDay = true
            activeDay = min(max(0, initialDay), max(0, days.count - 1))
        }
        .navigationDestination(isPresented: $openLog) { LogScreen() }
        .navigationDestination(isPresented: $openProgress) { ProgressScreen() }
        .alert("You can't log workouts yet", isPresented: $showLock) {
            Button("Cancel", role: .cancel) {}
            Button("I'm ready - start today") { Task { await startToday() } }
        } message: {
            Text("You can't log workouts before committing to training. Click here if you're ready to start today.")
        }
        .alert("Couldn't update your start date", isPresented: $lockFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    // MARK: Header

    private var header: some View {
        IntentPageHeader(program.programName) {
            HStack(spacing: 8) {
                Text("\(SplitType.format(program.splitType)) · Week \(program.weekNumber)")
                    .font(.intent(13.5, .regular))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .lineLimit(1)
                badge
            }
        } trailing: {
            HStack(spacing: 8) {
                // Progress lives here since Nutrition took its tab-bar slot.
                IntentIconButton("Progress", systemImage: "chart.xyaxis.line") { openProgress = true }
                if let onEdit {
                    IntentIconButton("Edit program", systemImage: "pencil", action: onEdit)
                }
            }
        }
    }

    // MARK: Hero

    private func hero(_ day: ProgramDay) -> some View {
        let lifts = ProgramWeek.liftExercises(day)
        let duration = ProgramWeek.sessionDuration(day, stats: durationStats)
        return VStack(spacing: 0) {
            // The glass and watermark are backgrounds so the (very wide) slogan
            // can't widen the layout; the card's own content sets the size.
            VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Image(systemName: "dumbbell")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Color.intent.sessionsCyan)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                        Spacer(minLength: 12)
                        Label {
                            Text("\(lifts.count) \(lifts.count == 1 ? "exercise" : "exercises")")
                        } icon: {
                            Image(systemName: "square.3.layers.3d").font(.system(size: 12, weight: .light))
                        }
                        .font(.intent(11.5, .regular))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .labelStyle(.titleAndIcon)
                    }
                    Spacer(minLength: 0)
                    Text("Day \(day.dayNumber)")
                        .font(.intent(12, .regular))
                        .tracking(12 * 0.12)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.75))
                    Text(day.focus)
                        .intentText(.heroTitle)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .frame(height: 196)
            .background(alignment: .topLeading) { ProgramHeroWatermark() }
            .background { ProgramHeroGlass() }
            .clipped()

            HStack(alignment: .top, spacing: 0) {
                stat(String(lifts.count), "Exercises", leadingRule: false)
                stat(String(ProgramWeek.totalSets(day)), "Sets", leadingRule: true)
                if let duration {
                    stat(duration, "Avg duration", leadingRule: true, clock: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Button(action: handleStartWorkout) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start workout")
                            .font(.intent(14, .medium))
                            .tracking(14 * 0.06)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.intent.foreground)
                        Text("\(day.label) · \(day.focus)")
                            .font(.intent(12, .regular))
                            .foregroundStyle(Color.intent.mutedForeground)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.black)
                        .offset(x: 1)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.white))
                }
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(ProgramStartRowStyle())
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .accessibilityIdentifier("button-start-workout-program")
        }
        .intentSurface(radius: IntentRadius.hero)
        .clipShape(RoundedRectangle(cornerRadius: IntentRadius.hero, style: .continuous))
    }

    private func stat(_ value: String, _ label: String, leadingRule: Bool, clock: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if clock {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Color.intent.mutedForeground)
                }
                Text(value)
                    .intentText(.statNumber)
                    .foregroundStyle(Color.intent.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .intentText(.caps)
                .foregroundStyle(Color.intent.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leadingRule ? 14 : 0)
        .overlay(alignment: .leading) {
            if leadingRule { IntentDivider(.vertical) }
        }
    }

    // MARK: Days + roster

    private var dayTabs: some View {
        VStack(alignment: .leading, spacing: 0) {
            IntentSectionTitle("Training days")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        IntentPill(d.label, isSelected: activeDay == i) { activeDay = i }
                            .accessibilityIdentifier("tab-day-\(d.dayNumber)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func roster(_ day: ProgramDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IntentSectionTitle("Exercises")
            IntentGroupedSection {
                ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, ex in
                    ProgramRosterRow(exercise: ex)
                }
            }
            .id("roster-\(activeDay)")
            .transition(.opacity.combined(with: .offset(x: 10)))
        }
    }

    // MARK: Start workout

    private func handleStartWorkout() {
        guard day != nil else { return }
        if Calibration.isPreCalibrationLocked(program, today: Date()) {
            showLock = true
            return
        }
        // NOTE (ported faithfully): the web's ProgramWeekView never reads
        // `canStartWorkout`, so Start workout also runs on the inactive lineage's page.
        // The web opens /log?day=N&start=1 (or the calibration briefing for a
        // calibration program) and records the active-session pointer first; the tab
        // shell's WorkoutLauncher does exactly that. Standalone debug screens have no
        // launcher, so they fall back to pushing the logger.
        if let launcher, let day {
            launcher.startDay(day.dayNumber)
        } else {
            openLog = true
        }
    }

    private func startToday() async {
        let body = Components.Schemas.ProgramStartDateUpdate(startDate: Calibration.localDateString(Date()))
        do {
            switch try await services.api.api.setProgramStartDate(path: .init(id: program.id), body: .json(body)) {
            case .ok: onProgramChanged?()
            default: lockFailed = true
            }
        } catch {
            lockFailed = true
        }
    }
}

/// One roster row: name over muscles (or the checklist category in its colour),
/// sets × reps as quiet trailing text. No numbering, no colour bars.
struct ProgramRosterRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .intentText(.rowTitle)
                    .foregroundStyle(Color.intent.foreground)
                    .lineLimit(1)
                subtitle
                    .font(.intent(12.5, .regular))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing = ProgramWeek.rosterTrailing(exercise) {
                Text(trailing)
                    .intentText(.rowValue)
                    .foregroundStyle(Color.intent.mutedForeground)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, IntentSpacing.rowVertical)
        .padding(.trailing, IntentSpacing.rowInset)
        .overlay(alignment: .top) { IntentDivider() }
        .padding(.leading, IntentSpacing.rowInset)
    }

    @ViewBuilder private var subtitle: some View {
        if exercise.kind == .checklist {
            let meta = ChecklistItems.categoryMeta(exercise.category)
            HStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 11))
                Text(meta?.label ?? "Checklist")
            }
            .foregroundStyle(Color.programChart(meta?.token ?? ChecklistItems.accent))
        } else {
            Text(ProgramWeek.rosterMuscles(exercise))
                .foregroundStyle(Color.intent.mutedForeground)
        }
    }
}

/// The Start-workout bottom-sheet row: `bg-secondary rounded-3xl`, accent when pressed.
struct ProgramStartRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous)
                    .fill(configuration.isPressed ? Color.intent.accent : Color.intent.secondary)
            )
    }
}

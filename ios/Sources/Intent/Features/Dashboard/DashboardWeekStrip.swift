import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// components/dashboard/WeekStrip.tsx: the brand and "Full month" on one row, then the
/// week on a shallow arc. A logged session is a solid white disc, a planned one is
/// outlined, a rest day only its dimmed number, and today the larger ringed circle
/// (the ring shows no progress). Tapping a day opens its detail sheet.
struct DashboardWeekStrip: View {
    let model: DashboardModel
    @Binding var openDate: String?

    private typealias Arc = DashboardLogic.Arc

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IntentBrandMark()
                Spacer(minLength: 0)
                NavigationLink {
                    CalendarScreen()
                } label: {
                    HStack(spacing: 4) {
                        Text("Full month").font(.intent(12))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.3)))
                }
                .buttonStyle(.plain)
            }

            let days = model.weekDays
            arc(days)
                .frame(maxWidth: 440)
                .frame(height: Arc.height)
                .padding(.top, 12)

            // A rotating cycle isn't pinned to weekdays, so name the sequence instead.
            if model.coreSchedule?.mode != .fixed, !model.coreProgramDays.isEmpty {
                (Text("In order: ").foregroundColor(Color.white.opacity(0.4))
                    + Text(model.coreProgramDays.map(\.label).joined(separator: " → ")).foregroundColor(Color.white.opacity(0.55)))
                    .font(.intent(11))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    private func arc(_ days: [WeekStripDay]) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(days.enumerated()), id: \.element.date) { i, day in
                    let offset = i - 3
                    let size = CGFloat(day.isToday ? Arc.todaySize : Arc.daySize)
                    let centerX = (CGFloat(i) + 0.5) / 7 * width
                    let top = CGFloat(Arc.y(offset: offset)) - size / 2 - CGFloat(day.isToday ? Arc.todayLift : 0)
                    Button {
                        openDate = day.date
                    } label: {
                        DashboardWeekDay(day: day)
                    }
                    .buttonStyle(DashboardPressScale())
                    .frame(width: 52)
                    .offset(x: centerX - 26, y: top)
                    .opacity(Arc.opacity(offset: offset))
                    .accessibilityLabel(DashboardLogic.accessibilityLabel(day))
                }
            }
            .frame(width: width, height: geo.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("This week")
    }
}

private struct DashboardWeekDay: View {
    let day: WeekStripDay

    var body: some View {
        let size = day.isToday ? DashboardLogic.Arc.todaySize : DashboardLogic.Arc.daySize
        VStack(spacing: 8) {
            Text("\(day.dayOfMonth)")
                .font(day.isToday ? Font.intent(21, .light) : Font.intent(14, day.done ? .medium : .regular))
                .tracking(day.isToday ? -0.42 : 0)
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .overlay {
                    if !day.done && !day.isToday && day.label != nil {
                        Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    }
                }
                .overlay {
                    if day.isToday {
                        // outline 1.5px at offset 2.5px
                        Circle().stroke(Color.white, lineWidth: 1.5).padding(-3.25)
                    }
                }
            Text(day.weekday)
                .font(.intent(10.5, day.isToday ? .semibold : .regular))
                .tracking(1.26)
                .textCase(.uppercase)
                .foregroundStyle(day.isToday ? Color.white : Color.white.opacity(0.55))
        }
    }

    private var fill: Color {
        if day.done { return .white }
        if day.isToday { return Color.black.opacity(0.35) }
        if day.label != nil { return Color.black.opacity(0.2) }
        return .clear
    }

    private var numberColor: Color {
        if day.done { return .black }
        if day.isToday || day.label != nil { return .white }
        return Color.white.opacity(0.4)
    }
}

/// `group-active:scale-95` on the day circle.
struct DashboardPressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Day detail sheet

/// components/dashboard/DayDetailSheet.tsx: a tapped day's sessions (or what the
/// program pencils in) and its calories / steps / cardio / weight.
struct DashboardDayDetailSheet: View {
    let day: WeekStripDay
    let entry: IntentSchemas.DailyLogWeekEntry?
    let sessions: [IntentSchemas.WorkoutLog]
    /// AI mode only.
    let phase: String?
    let weightUnit: String
    let colorFor: (String) -> Color
    let openCalendar: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateLabel)
                            .font(.intent(17))
                            .tracking(-0.17)
                            .foregroundStyle(Color.intent.foreground)
                        Text(statusLine)
                            .intentText(.caption)
                            .foregroundStyle(Color.intent.mutedForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let phase {
                        Text(PhaseColors.label(phase).capitalized)
                            .font(.intent(10, .medium))
                            .foregroundStyle(dashboardPhaseColor(phase))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(dashboardPhaseColor(phase, opacity: PhaseColors.softAlpha)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

                VStack(spacing: 8) {
                    ForEach(sessions, id: \.id) { session in
                        sessionRow(session)
                    }
                    if sessions.isEmpty, let planned = day.planned {
                        HStack(spacing: 12) {
                            Circle().fill(colorFor(planned.label)).opacity(0.6).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(planned.label).intentText(.rowTitle)
                                    .foregroundStyle(Color.intent.foreground.opacity(0.8)).lineLimit(1)
                                Text("On your program for this day").intentText(.caption)
                                    .foregroundStyle(Color.intent.mutedForeground)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.intent.secondary.opacity(0.6)))
                    }
                }
                .padding(.horizontal, 20)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(stats, id: \.0) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.0).font(.intent(10.5)).tracking(1.05).textCase(.uppercase)
                                .foregroundStyle(Color.intent.mutedForeground)
                            Text(stat.1)
                                .font(.intent(18, .light))
                                .tracking(-0.18)
                                .monospacedDigit()
                                .foregroundStyle(Color.intent.foreground)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.intent.secondary))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func sessionRow(_ session: IntentSchemas.WorkoutLog) -> some View {
        let label = session.dayLabel ?? "Workout"
        let count = dashboardExerciseCount(session)
        return Button(action: openCalendar) {
            HStack(spacing: 12) {
                Circle().fill(colorFor(label)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).intentText(.rowTitle).foregroundStyle(Color.intent.foreground).lineLimit(1)
                    Text("\(count) exercise\(count == 1 ? "" : "s")").intentText(.caption)
                        .foregroundStyle(Color.intent.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.intent.chart2)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.intent.mutedForeground)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(DashboardSurfaceButtonStyle())
    }

    private var dateLabel: String {
        // toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" })
        guard let d = Calibration.parseLocalDateString(day.date) else { return day.date }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: d)
    }

    private var statusLine: String {
        if !sessions.isEmpty { return "\(sessions.count) session\(sessions.count == 1 ? "" : "s") logged" }
        return day.planned != nil ? "Planned - not logged yet" : "Rest day"
    }

    private var stats: [(String, String)] {
        var cardio = "-"
        if let type = entry?.cardioType, !type.isEmpty {
            cardio = type + (entry?.cardioMinutes.map { " · \($0) min" } ?? "")
        }
        return [
            ("Calories", entry?.calories.map(DashboardFormat.grouped) ?? "-"),
            ("Steps", entry?.steps.map(DashboardFormat.grouped) ?? "-"),
            ("Cardio", cardio),
            ("Weight", entry?.weight.map { "\(DashboardFormat.js($0)) \(weightUnit)" } ?? "-"),
        ]
    }
}

/// `exerciseCount`: checklist items count; a lift counts once it has a set with a
/// number (a calibration set only needs its tick).
func dashboardExerciseCount(_ session: IntentSchemas.WorkoutLog) -> Int {
    let calibration = session.loggingMode == .calibration
    return session.exercisesLogged.filter { ex in
        if ex.kind == .checklist { return true }
        return ex.sets.contains { s in
            calibration ? s.completed
                : (s.weight != 0 || (s.reps ?? 0) != 0 || (s.repsLeft ?? 0) != 0 || (s.repsRight ?? 0) != 0)
        }
    }.count
}

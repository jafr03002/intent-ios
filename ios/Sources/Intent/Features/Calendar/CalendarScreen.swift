import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// Debug states CI screenshots (see DebugScreen).
enum CalendarDebug {
    case none
    /// Open the newest logged session's sheet.
    case openLatest
    /// ...and its delete confirm.
    case deleteConfirm
    /// Show last month.
    case previousMonth
}

/// /calendar (port of pages/calendar.tsx): the storm wash, a plain month switcher,
/// the month grid with phase bands and the glass day lens, the calibration-review
/// notice, a list for days with several sessions, and the session sheet.
///
/// Not ported: the first-run calendar coachmark tour (`calendarTourSeenAt`) - tours
/// are a cross-screen feature with no native component yet.
struct CalendarScreen: View {
    @Environment(AppServices.self) private var services
    @State private var data = CalendarData()
    @State private var year: Int
    @State private var month0: Int
    @State private var selectedDate: String
    @State private var openSession: CalendarSessionItem?
    private let debug: CalendarDebug

    init(debug: CalendarDebug = .none) {
        let now = Date()
        let ym = CalendarMonth.yearMonth(of: now)
        _year = State(initialValue: ym.year)
        _month0 = State(initialValue: ym.month0)
        _selectedDate = State(initialValue: ProgramScheduleReader.todayDateString(at: now))
        self.debug = debug
    }

    var body: some View {
        let state = CalendarViewState(data: data, year: year, month0: month0, now: Date())
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    brandRow(state)
                    titleBlock(state)
                    monthSwitcher(state)
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(spacing: 6) {
                            weekdayHeader
                            CalendarMonthGrid(
                                padding: state.padding, days: state.days, selected: selectedDate,
                                onTap: { tap($0, state: state) },
                                onSelect: { date in withAnimation(Self.lensSpring) { selectedDate = date } })
                        }
                        if let notice = state.calibrationNotice {
                            noticeCard(notice, icon: "info.circle")
                        }
                        if data.loadFailed && !data.isLoading {
                            noticeCard("Couldn't load your sessions. Pull down to try again.", icon: "exclamationmark.circle")
                        }
                        let sessions = state.sessions(on: selectedDate)
                        if sessions.count > 1 {
                            sessionList(sessions, state: state)
                                .id(selectedDate)
                                .transition(.opacity.combined(with: .offset(y: 8)))
                        }
                    }
                }
                .padding(IntentSpacing.gutter)
            }
            .scrollIndicators(.hidden)
            .refreshable { await data.load(services.api) }
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Color.black
                    CalendarWash(sunX: sunX(state, width: geo.size.width))
                        .frame(height: 420 + geo.safeAreaInsets.top)
                }
                .ignoresSafeArea()
            }
        }
        .foregroundStyle(Color.intent.foreground)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openSession) { item in
            CalendarSessionSheet(
                session: item.log, allWorkouts: data.workouts,
                color: CalendarPaint.color(hex: state.colorHex(item.log.dayLabel ?? "Workout")),
                onDelete: { try await deleteSession(item.log) },
                onClose: { openSession = nil },
                startWithDeleteConfirm: debug == .deleteConfirm)
            .presentationDetents([.fraction(0.88), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .presentationBackground(Color.intent.card)
        }
        .task {
            await data.load(services.api)
            await applyDebug()
        }
    }

    static let lensSpring = Animation.spring(response: 0.42, dampingFraction: 0.74)

    // MARK: Header

    private func brandRow(_ state: CalendarViewState) -> some View {
        HStack {
            HStack(spacing: 7) {
                IntentSunMark(size: 20)
                Text("Intent").font(.intent(16)).foregroundStyle(Color.white)
            }
            Spacer()
            Button(action: goToday) {
                Text("Today")
                    .font(.intent(13))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(state.viewingThisMonth && selectedDate == state.todayString)
            .opacity(state.viewingThisMonth && selectedDate == state.todayString ? 0.4 : 1)
            .accessibilityIdentifier("calendar-today")
        }
    }

    private func titleBlock(_ state: CalendarViewState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calendar").intentText(.screenTitle)
            ProgressFlowRow(spacing: 12, lineSpacing: 8) {
                Text("\(state.sessionsInMonth) session\(state.sessionsInMonth == 1 ? "" : "s") in \(CalendarMonth.monthName(month0))")
                    .font(.intent(13.5))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                if let range = state.todayRange {
                    HStack(spacing: 6) {
                        Circle().fill(CalendarPaint.phase(range.phase)).frame(width: 6, height: 6)
                        Text("\(PhaseColors.label(range.phase)) phase")
                        if let week = state.todayWeek {
                            Text("· week \(week)").foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                    .intentText(.badge)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .accessibilityIdentifier("calendar-current-phase")
                }
            }
        }
    }

    private func monthSwitcher(_ state: CalendarViewState) -> some View {
        HStack {
            chevron("chevron.left", label: "Previous month") { goToMonth(by: -1) }
            Spacer()
            Text(CalendarMonth.monthTitle(year: year, month0: month0))
                .font(.intent(17))
                .tracking(-0.17)
                .foregroundStyle(Color.white)
                .id(CalendarMonth.monthTitle(year: year, month0: month0))
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                                        removal: .opacity.combined(with: .offset(y: -6))))
            Spacer()
            chevron("chevron.right", label: "Next month") { goToMonth(by: 1) }
        }
        .padding(.horizontal, -10)
    }

    private func chevron(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(CalendarMonth.weekdayInitials.enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(.intent(10.5))
                    .tracking(1.05)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Below the grid

    private func noticeCard(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.intent.mutedForeground)
            Text(text)
                .intentText(.caption)
                .foregroundStyle(Color.intent.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .intentSurface(radius: IntentRadius.notice)
    }

    private func sessionList(_ sessions: [WorkoutLog], state: CalendarViewState) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { i, session in
                let label = session.dayLabel ?? "Workout"
                let hasNotes = session.exercisesLogged.contains { !($0.notes ?? "").isEmpty }
                Button { openSession = CalendarSessionItem(log: session) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(CalendarPaint.color(hex: state.colorHex(label))).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label).intentText(.rowTitle).lineLimit(1)
                            HStack(spacing: 6) {
                                Text(CalendarMonth.sessionSummary(session)).lineLimit(1)
                                if hasNotes {
                                    Image(systemName: "text.bubble").font(.system(size: 10)).accessibilityLabel("Has notes")
                                }
                            }
                            .font(.intent(12.5))
                            .foregroundStyle(Color.intent.mutedForeground)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.intent.mutedForeground)
                    }
                    .padding(.vertical, 15)
                    .padding(.trailing, 20)
                    .overlay(alignment: .bottom) { if i < sessions.count - 1 { IntentDivider() } }
                    .padding(.leading, 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-agenda-session-\(session.id)")
            }
        }
        .intentSurface(radius: IntentRadius.groupedList)
    }

    // MARK: Actions

    /// A tap both selects and opens: only a day with several sessions needs the list.
    private func tap(_ date: String, state: CalendarViewState) {
        if date != selectedDate { withAnimation(Self.lensSpring) { selectedDate = date } }
        let sessions = state.sessions(on: date)
        if sessions.count == 1 { openSession = CalendarSessionItem(log: sessions[0]) }
    }

    private func goToMonth(by delta: Int) {
        let next = CalendarMonth.shiftMonth(year: year, month0: month0, by: delta)
        show(year: next.year, month0: next.month0)
    }

    private func goToday() {
        let ym = CalendarMonth.yearMonth(of: Date())
        show(year: ym.year, month0: ym.month0)
    }

    /// Land on today in that month, otherwise the 1st.
    private func show(year y: Int, month0 m: Int) {
        let today = ProgramScheduleReader.todayDateString()
        let first = CalendarMonth.dateKey(year: y, month0: m, day: 1)
        withAnimation(.easeOut(duration: 0.18)) {
            year = y
            month0 = m
            selectedDate = today.hasPrefix(String(first.prefix(7))) ? today : first
        }
    }

    private func deleteSession(_ log: WorkoutLog) async throws {
        try await data.delete(log.id, client: services.api)
        await data.reloadWorkouts(services.api)
    }

    private func sunX(_ state: CalendarViewState, width: CGFloat) -> CGFloat {
        guard width > 0, let index = state.days.firstIndex(where: { $0.date == selectedDate }) else { return 0.5 }
        let col = CGFloat((state.padding + index) % 7)
        let grid = width - 2 * IntentSpacing.gutter
        return (IntentSpacing.gutter + (col + 0.5) * grid / 7) / width
    }

    private func applyDebug() async {
        switch debug {
        case .none: break
        case .previousMonth: goToMonth(by: -1)
        case .openLatest, .deleteConfirm:
            let latest = JSLikeSort.newestFirst(data.workouts).first
            guard let latest else { return }
            if let ym = Self.yearMonth(latest.date) { year = ym.0; month0 = ym.1 }
            selectedDate = latest.date
            try? await Task.sleep(for: .milliseconds(300))
            openSession = CalendarSessionItem(log: latest)
        }
    }

    private static func yearMonth(_ date: String) -> (Int, Int)? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1] - 1)
    }
}

private enum JSLikeSort {
    static func newestFirst(_ logs: [WorkoutLog]) -> [WorkoutLog] {
        logs.sorted { a, b in a.date == b.date ? a.id > b.id : a.date > b.date }
    }
}

/// Everything the calendar derives from its data for one render (the web's top-level
/// `Calendar()` body).
struct CalendarViewState {
    let todayString: String
    let padding: Int
    let days: [CalendarMonth.Day]
    let sessionsInMonth: Int
    let viewingThisMonth: Bool
    let todayRange: PhaseRange?
    let todayWeek: Int?
    let calibrationNotice: String?
    private let byDate: [String: [WorkoutLog]]
    private let colorOrder: [String: Int]
    private let customColors: [String: String]

    @MainActor
    init(data: CalendarData, year: Int, month0: Int, now: Date) {
        let todayString = ProgramScheduleReader.todayDateString(at: now)
        let todayMidnight = Calendar.current.startOfDay(for: now)
        self.todayString = todayString

        let ranges = data.profileLoaded
            ? CalendarMonth.phaseRanges(isIndependent: data.isIndependent, goal: data.goal, programs: data.programs,
                                        onboardingCompletedAt: data.onboardingCompletedAt, now: now)
            : []
        let active = Calibration.findCalibrationGroup(Calibration.buildCalibrationGroups(ranges), todayMidnight)

        var byDate: [String: [WorkoutLog]] = [:]
        var labels: [String] = []
        for w in data.workouts {
            byDate[w.date, default: []].append(w)
            if let l = w.dayLabel, !l.isEmpty, !labels.contains(l) { labels.append(l) }
        }
        self.byDate = byDate
        colorOrder = DayColors.buildDayColorOrder(programLabels: data.programDays.map(\.label), extraLabels: labels)
        customColors = data.customColors

        // Only a fixed weekly schedule can say what a future day holds.
        let schedule = data.schedule
        let startDate = data.programStartDate
        let programDays = data.programDays
        let plannedLabelOn: (String) -> String? = { date in
            guard schedule?.mode == .fixed,
                  let n = ProgramScheduleReader.resolveDayForDate(schedule, startDate: startDate, date: date) else { return nil }
            return programDays.first { $0.dayNumber == n }?.label
        }

        padding = CalendarMonth.startPadding(year: year, month0: month0)
        days = CalendarMonth.buildDays(year: year, month0: month0, todayString: todayString,
                                       sessionsByDate: byDate.mapValues { $0.map(\.dayLabel) },
                                       ranges: ranges, activeCalibrationGroup: active, plannedLabelOn: plannedLabelOn)
        sessionsInMonth = days.reduce(0) { $0 + (byDate[$1.date]?.count ?? 0) }
        let ym = CalendarMonth.yearMonth(of: now)
        viewingThisMonth = ym.year == year && ym.month0 == month0

        let todayRange = CalendarMonth.visiblePhase(on: todayMidnight, ranges: ranges, activeCalibrationGroup: active)
        self.todayRange = todayRange
        todayWeek = todayRange.flatMap { CalendarMonth.phaseWeek($0, on: todayMidnight) }

        if let active {
            let reviewFrom = Calibration.addDays(active.start, 7)
            calibrationNotice = Calibration.isReviewPossible(active, todayMidnight)
                ? "Calibration review possible."
                : "Calibration review possible from \(CalendarMonth.dayMonth(reviewFrom))."
        } else {
            calibrationNotice = nil
        }
    }

    func sessions(on date: String) -> [WorkoutLog] { byDate[date] ?? [] }

    /// The colour a day wears on the program page and in the editor.
    func colorHex(_ label: String) -> String {
        DayColors.dayColorHex(label, order: colorOrder, custom: customColors)
    }
}

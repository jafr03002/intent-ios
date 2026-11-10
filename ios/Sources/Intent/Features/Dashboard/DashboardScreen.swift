import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// The Home tab: port of pages/dashboard.tsx (Sessions). Top to bottom: the week on
/// an arc over the wash, the greeting, the hero (current week, PRs this week, Start
/// workout), the weekly check-in banner (AI), this week's targets (AI narrative or
/// Independent's editable card), today's check-in (bodyweight, calories, steps,
/// cardio) and progress toward goal. Two takeovers replace it: the pre-calibration
/// lock and the one-time calibration walkthrough.
///
/// Not ported yet: the first-run coachmark tours (dashboard + calendar nudge), and
/// the live WebGL wash (the static `.sessions-wash` fallback is drawn instead).
struct DashboardScreen: View {
    @Environment(AppServices.self) private var services
    @State private var model = DashboardModel()
    @State private var openDate: String?
    @State private var showCalendar = false
    private let debug = DashboardDebugOptions.fromLaunchArguments()

    var body: some View {
        content
            .background(Color.intent.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showCalendar) { CalendarScreen() }
            .task {
                guard !model.isLoaded else { return }
                await model.load(client)
                if debug.openTodaySheet { openDate = model.today }
            }
    }

    /// The services' client, or (debug variants in mock mode) another fixture scenario.
    private var client: IntentAPIClient {
        if services.isMock, let scenario = debug.scenario {
            return IntentAPIClient(environment: .production, transport: FixtureTransport(scenario: scenario))
        }
        return services.api
    }

    @ViewBuilder private var content: some View {
        if !model.isLoaded {
            page { loadingTop }
        } else if model.isPreCalibrationLocked, let program = model.program {
            page {
                DashboardPreCalibrationLock(name: displayName, startDate: program.startDate ?? "") {
                    await startToday(program.id)
                }
            }
        } else if let start = model.walkthroughStart {
            DashboardCalibrationWalkthrough(calibrationStart: start, initialStep: debug.walkthroughStep) {
                await finishWalkthrough()
            }
        } else {
            dashboard
        }
    }

    private var displayName: String { (model.profile?.name).flatMap { $0.isEmpty ? nil : $0 } ?? "Coach" }

    // MARK: Page frame

    /// `DashboardShell`: black page, the wash behind the top 420pt reaching up under
    /// the status bar, `p-6` gutter, `space-y-6`.
    private func page<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let built = content()
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: IntentSpacing.section) {
                    built
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(IntentSpacing.gutter)
                .background(alignment: .top) {
                    DashboardWash().frame(height: 420 + 120).offset(y: -120)
                }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(debug.scrollAnchor == .bottom && model.isLoaded ? .bottom : .top)
            .foregroundStyle(Color.intent.foreground)
            .task {
                // Debug variants open scrolled so CI sees the whole page.
                guard model.isLoaded, let anchor = debug.scrollAnchor, anchor != .bottom else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo(anchor.id, anchor: anchor.unitPoint)
            }
        }
    }

    private var loadingTop: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { IntentBrandMark(); Spacer() }
            Color.clear.frame(height: DashboardLogic.Arc.height + 12)
        }
    }

    // MARK: The dashboard

    private var dashboard: some View {
        page {
            DashboardWeekStrip(model: model, openDate: $openDate)
                .id(DashboardAnchor.top.id)
            greeting
            hero
            if model.showCheckinBanner { checkinBanner }
            if !model.isIndependent, let program = model.program, program.aiGenerated,
               program.shortTermPhase != nil || program.dailyCalorieTarget != nil || program.dailyStepTarget != nil {
                narrative(program)
            }
            if model.isIndependent, let profile = model.profile {
                DashboardIndependentTargets(model: model, client: client, profile: profile,
                                            startEditing: debug.editTargets)
                    .id(DashboardAnchor.targets.id)
            }
            DashboardDailyCheckin(model: model, client: client)
                .id(DashboardAnchor.checkin.id)
            progressSection
                .id(DashboardAnchor.bottom.id)
        }
        .sheet(item: Binding(get: { openDate.map(DashboardSheetDate.init) }, set: { openDate = $0?.date })) { item in
            daySheet(item.date)
        }
    }

    private var greeting: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                DashboardEyebrow(text: DashboardLogic.greeting())
                DashboardTitle(text: displayName)
                Text(greetingLine)
                    .intentText(.lede)
                    .foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Phases only exist in the AI lineage - never label an independent dashboard.
            if !model.isIndependent, let phase = model.program?.shortTermPhase?.rawValue {
                DashboardPhasePill(phase: phase).padding(.bottom, 4)
            }
        }
    }

    private var greetingLine: String {
        if model.program != nil, let next = model.nextDay { return GreetingLines.greetingLine(dayLabel: next.label) }
        if let stats = model.stats { return "Week \(stats.currentWeek) of your program." }
        return "Start logging your workouts here and get to work."
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                heroStat(model.stats.map { "\($0.currentWeek)" } ?? "-", "Current week")
                IntentDivider(.vertical)
                heroStat("\(model.recentPrCount)", "PRs this week")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 16)

            Group {
                if model.program == nil {
                    NavigationLink {
                        ProgramScreen()
                    } label: {
                        DashboardHeroActionLabel(
                            title: model.isIndependent ? "Build your program" : "Generate a program",
                            subtitle: model.isIndependent ? "Set up your training days" : "Your coach writes it from your answers",
                            systemImage: "chevron.right")
                    }
                    .buttonStyle(DashboardSurfaceButtonStyle())
                } else if let next = model.nextDay {
                    // To the program page, not straight into the logger: a session only
                    // starts from the day's Start workout button there.
                    NavigationLink {
                        ProgramScreen()
                    } label: {
                        DashboardHeroActionLabel(title: "Start workout", subtitle: next.label, systemImage: "play.fill")
                    }
                    .buttonStyle(DashboardSurfaceButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .intentSurface(radius: IntentRadius.hero)
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).intentText(.statNumber).monospacedDigit().foregroundStyle(Color.intent.foreground)
            Text(label).intentText(.caps).foregroundStyle(Color.intent.mutedForeground).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    // MARK: Weekly check-in banner (AI)

    private var checkinBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time for your weekly check-in").font(.intent(14, .medium)).foregroundStyle(Color.intent.foreground)
                Text("Your AI coach will adjust next week's program based on your answers")
                    .font(.intent(12.5)).lineSpacing(4).foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink("Start") { CheckinScreen() }
                .buttonStyle(DashboardSmallPillStyle(primary: true))
        }
        .padding(.vertical, 14)
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .intentSurface(radius: IntentRadius.notice)
    }

    // MARK: This week (AI narrative)

    private func narrative(_ program: IntentSchemas.Program) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 8) {
                    if let phase = program.shortTermPhase?.rawValue {
                        Circle().fill(dashboardPhaseColor(phase)).frame(width: 6, height: 6)
                    }
                    Text(program.shortTermPhase.map { PhaseColors.label($0.rawValue).capitalized } ?? "This week")
                        .intentText(.sectionTitle)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let week = program.weekInPhase {
                    Text("Week \(week)\(program.phaseTotalWeeks.map { " of \($0)" } ?? "")")
                        .intentText(.caption)
                        .foregroundStyle(Color.intent.mutedForeground)
                        .fixedSize()
                }
            }
            .padding(.bottom, IntentSpacing.sectionTitle)
            IntentGroupedSection {
                if let kcal = program.dailyCalorieTarget {
                    IntentGroupedRow("Calorie target", value: "\(DashboardFormat.grouped(kcal)) kcal / day")
                }
                if let steps = program.dailyStepTarget {
                    IntentGroupedRow("Step target", value: "\(DashboardFormat.grouped(steps)) steps / day")
                }
            }
        }
    }

    // MARK: Progress toward goal

    private var progressSection: some View {
        let unit = model.profile?.weightUnit ?? "kg"
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                ProgressScreen()
            } label: {
                HStack(spacing: 6) {
                    Text("Progress toward goal").intentText(.sectionTitle).foregroundStyle(Color.intent.foreground)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.intent.mutedForeground)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, IntentSpacing.sectionTitle)

            VStack(alignment: .leading, spacing: 0) {
                if let goal = model.goal {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            (Text(DashboardFormat.fixed1(goal.currentTrendWeight)).font(.intent(40, .light)).tracking(-1.2)
                                + Text(" \(unit)").font(.intent(15)).foregroundColor(Color.intent.mutedForeground))
                                .monospacedDigit()
                                .foregroundStyle(Color.intent.foreground)
                            Text("Trend weight").intentText(.caps).foregroundStyle(Color.intent.mutedForeground)
                        }
                        Spacer(minLength: 0)
                        if let toGo = DashboardLogic.toGo(trendWeight: goal.currentTrendWeight, goalWeight: goal.goalWeight) {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(DashboardFormat.fixed1(toGo)) \(unit)").font(.intent(20, .light)).tracking(-0.2)
                                    .monospacedDigit().foregroundStyle(Color.intent.foreground)
                                Text("to go").intentText(.caps).foregroundStyle(Color.intent.mutedForeground)
                            }
                            .fixedSize()
                        }
                    }
                    if let goalWeight = goal.goalWeight, let pct = goal.percentToGoal {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.intent.secondary)
                                // NOTE (ported): the web sets width: pct% unclamped.
                                Capsule().fill(Color.white).frame(width: max(0, geo.size.width * CGFloat(pct) / 100))
                            }
                        }
                        .frame(height: 6)
                        .clipShape(Capsule())
                        .padding(.top, 20)
                        .padding(.bottom, 10)
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(DashboardFormat.js(goal.startWeight)) \(unit)").font(.intent(13, .medium))
                                    .foregroundStyle(Color.intent.foreground)
                                Text("started \(DashboardFormat.date(goal.startDate, "MMM d"))")
                            }
                            Spacer(minLength: 0)
                            Text("\(Int(pct.rounded()))% there").frame(maxHeight: .infinity)
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(DashboardFormat.js(goalWeight)) \(unit)").font(.intent(13, .medium))
                                    .foregroundStyle(Color.intent.foreground)
                                Text(goal.targetDate.map { "~\(DashboardFormat.date($0, "MMM d")) at this rate" } ?? "still calibrating")
                            }
                            .multilineTextAlignment(.trailing)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.intent(11.5))
                        .foregroundStyle(Color.intent.mutedForeground)
                    }
                } else {
                    Text("Log your bodyweight to start tracking progress")
                        .intentText(.caption)
                        .foregroundStyle(Color.intent.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(20)
            .intentSurface(radius: IntentRadius.groupedList)
        }
    }

    // MARK: Day sheet

    private func daySheet(_ date: String) -> some View {
        let day = model.weekDays.first { $0.date == date }
        return Group {
            if let day {
                DashboardDayDetailSheet(
                    day: day,
                    entry: model.entry(for: date),
                    sessions: model.workouts.filter { $0.date == date },
                    phase: model.isIndependent ? nil : model.week?.shortTermPhase?.rawValue,
                    weightUnit: model.profile?.weightUnit ?? "kg",
                    colorFor: { dashboardColor(hex: model.dayColorHex($0)) },
                    openCalendar: {
                        openDate = nil
                        showCalendar = true
                    })
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(IntentRadius.hero)
        .presentationBackground(Color.intent.card)
        .preferredColorScheme(.dark)
    }

    // MARK: Actions

    private func startToday(_ id: Int) async -> Bool {
        do {
            let today = Calibration.localDateString(Date())
            _ = try await client.api.setProgramStartDate(path: .init(id: id), body: .json(.init(startDate: today))).ok.body.json
        } catch {
            return false
        }
        await model.reloadProgram(client)
        // Starting moves day 1; mirror it locally too (the mock backend is stateless).
        let today = Calibration.localDateString(Date())
        if model.program?.id == id { model.program?.startDate = today }
        if let i = model.programs.firstIndex(where: { $0.id == id }) { model.programs[i].startDate = today }
        return true
    }

    private func finishWalkthrough() async -> Bool {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = iso.string(from: Date())
        do {
            _ = try await client.api.updateProfile(body: .json(.init(calibrationWalkthroughSeenAt: now))).ok.body.json
        } catch {
            return false
        }
        model.walkthroughFinished = true
        return true
    }
}

/// `openDate` as a sheet item.
private struct DashboardSheetDate: Identifiable {
    let date: String
    var id: String { date }
}

import IntentAPI
import IntentCore
import IntentDesign
import Observation
import SwiftUI

/// Where the logger was asked to open: the web's `/log?day=N&start=1&resumed=1`.
struct LogRoute: Identifiable, Equatable {
    let id = UUID()
    var request: LogRequest
    /// Debug only: open with the calibration finish sheet up.
    var debugShowCalibrationFinish = false
}

/// A toast at the top of the screen (the web's `toast()`).
struct LogToast: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var description: String
    var isError = false
}

/// The workout-session hub the tab shell owns: the one draft store, the session in
/// progress (for the live Start disc), and where /log and the calibration briefing
/// open. The web spreads this over components/layout.tsx (Start, the picker,
/// `useActiveSession`) and wouter routes; here MainTabView holds one of these and
/// the Log feature's views read it from the environment.
///
/// Other features open the logger through it, e.g. the program page's Start workout:
/// `launcher.startDay(dayNumber)` (it routes calibration days to the briefing).
@MainActor
@Observable
final class WorkoutLauncher {
    /// The session in progress, if any (useActiveSession).
    private(set) var active: ActiveSessionSummary?
    /// Non-nil while the logger is open.
    var route: LogRoute?
    /// Non-nil while the calibration briefing is open (its day number).
    var briefingDay: Int?
    var toast: LogToast?
    /// Ticks once a second while a session runs, for the disc's clock.
    var now: Double = logNowMs()

    /// The program Start picks from (the active mode's lineage, as the log page uses).
    private(set) var program: Program?
    private(set) var profile: LogProfile?
    var userId: String? { profile?.userId }

    @ObservationIgnored private(set) var client: Client?
    @ObservationIgnored private let apiOverride: IntentAPIClient?
    @ObservationIgnored private(set) var store: WorkoutSessionStore!
    /// Set by the tab shell so a finished/cancelled session can land on a tab.
    @ObservationIgnored var selectTab: ((IntentTabBar.Tab) -> Void)?
    @ObservationIgnored private var attached = false

    /// - Parameter api: debug override (e.g. another fixture scenario); nil uses the app's client.
    init(api: IntentAPIClient? = nil, keyValueStore: KeyValueStore = LogUserDefaultsStore()) {
        apiOverride = api
        client = api?.api
        store = WorkoutSessionStore(store: keyValueStore, onActiveSessionChange: { [weak self] in
            MainActor.assumeIsolated { self?.refreshActive() }
        })
    }

    /// Wire to the app's services (once) and load what Start needs.
    func attach(_ services: AppServices) async {
        if client == nil { client = (apiOverride ?? services.api).api }
        guard !attached, let client else { return }
        attached = true
        async let profile = try? LogAPI.profile(client)
        async let program = try? LogAPI.program(client)
        self.profile = await profile
        self.program = await program
        refreshActive()
    }

    /// Re-read the program (e.g. after the picker found none, or a start date moved).
    /// A 404 clears it; a failed request keeps what we had.
    func reloadProgram() async {
        guard let client else { return }
        do {
            program = try await LogAPI.program(client)
        } catch {
            appLog.error("start: program reload failed: \(String(describing: error), privacy: .public)")
        }
    }

    func refreshActive() {
        let next = store.activeSessionSummary(userId: userId)
        if next != active { active = next }
    }

    // MARK: Start

    /// The tab bar's Start: resume a running session, else toggle the picker, else
    /// (nothing to pick from) go to the program page.
    func handleStart(pickerOpen: Binding<Bool>) {
        refreshActive()
        if active != nil {
            pickerOpen.wrappedValue = false
            resume()
            return
        }
        if pickerOpen.wrappedValue {
            pickerOpen.wrappedValue = false
            return
        }
        switch LogScreenRules.startPress(program: program, today: Date()) {
        case .openPicker:
            pickerOpen.wrappedValue = true
            // The web's query refetches; keep the picker's days fresh the same way.
            Task { await reloadProgram() }
        case .goToProgram:
            // The program is only read once at launch, so a user who onboarded or
            // built one since would never get the picker. Re-read before deciding.
            Task {
                await reloadProgram()
                if LogScreenRules.startPress(program: program, today: Date()) == .openPicker {
                    pickerOpen.wrappedValue = true
                } else {
                    closeLog()
                    selectTab?(.program)
                }
            }
        }
    }

    /// A day picked from the picker (or the program page's Start workout).
    func startDay(_ dayNumber: Int) {
        guard let program else { return }
        switch LogScreenRules.pickRoute(program: program, dayNumber: dayNumber) {
        case .briefing(let day):
            briefingDay = day
        case .startSession(let day):
            startSessionNow(dayNumber: day)
        }
    }

    /// The deliberate press that begins a session, then the logger with `start=1`
    /// so it still begins the day if the write didn't land.
    func startSessionNow(dayNumber: Int) {
        if let userId, let program { store.startSession(userId: userId, programId: program.id, dayNumber: dayNumber) }
        route = LogRoute(request: LogRequest(targetDayNumber: dayNumber, startRequested: true))
    }

    func resume() {
        guard let active else { return }
        route = LogRoute(request: LogRequest(targetDayNumber: active.dayNumber))
    }

    func open(_ request: LogRequest) { route = LogRoute(request: request) }

    func closeLog() { route = nil }

    /// The logger is done (saved or discarded): show the toast, land on a tab.
    func sessionEnded(toast: LogToast?, goTo tab: IntentTabBar.Tab) {
        refreshActive()
        route = nil
        selectTab?(tab)
        if let toast { show(toast) }
    }

    func show(_ toast: LogToast) {
        self.toast = toast
        let id = toast.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.toast?.id == id { self?.toast = nil }
        }
    }

    /// The briefing was read through (first time): remember it, as the web does.
    func markBriefingSeen() {
        guard profile?.calibrationBriefingSeenAt == nil, let client else { return }
        let stamp = Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        profile?.calibrationBriefingSeenAt = stamp
        Task {
            _ = try? await client.updateProfile(body: .json(.init(calibrationBriefingSeenAt: stamp)))
        }
    }
}

// MARK: - Shell chrome

extension View {
    /// Everything the workout launcher adds to the tab shell: the environment, the
    /// calibration briefing (full screen, over the tab bar), toasts, and the clocks.
    func workoutLauncherChrome(_ launcher: WorkoutLauncher, selectTab: @escaping (IntentTabBar.Tab) -> Void) -> some View {
        modifier(WorkoutLauncherChrome(launcher: launcher, selectTab: selectTab))
    }
}

private struct WorkoutLauncherChrome: ViewModifier {
    let launcher: WorkoutLauncher
    let selectTab: (IntentTabBar.Tab) -> Void
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(launcher)
            .overlay(alignment: .top) { LogToastStack(toast: launcher.toast) }
            .fullScreenCover(item: Binding(
                get: { launcher.briefingDay.map(BriefingItem.init) },
                set: { launcher.briefingDay = $0?.dayNumber }
            )) { item in
                CalibrationBriefingScreen(dayNumber: item.dayNumber)
                    .environment(launcher)
                    .environment(services)
            }
            .task {
                launcher.selectTab = selectTab
                await launcher.attach(services)
            }
            .task(id: launcher.active?.startedAt) {
                // The disc's clock: derived from startedAt every tick, never counted.
                guard launcher.active?.startedAt != nil else { return }
                while !Task.isCancelled {
                    launcher.now = logNowMs()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // A draft may have aged past a day while the app was away.
                if phase == .active { launcher.refreshActive() }
            }
    }

    private struct BriefingItem: Identifiable {
        let dayNumber: Int
        var id: Int { dayNumber }
    }
}

/// The toast pill at the top: the web's shadcn toast, in Sessions grey.
struct LogToastStack: View {
    let toast: LogToast?

    var body: some View {
        VStack {
            if let toast {
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.intent(14, .medium))
                        .foregroundStyle(toast.isError ? Color.intent.destructive : Color.intent.foreground)
                    Text(toast.description)
                        .intentText(.caption)
                        .foregroundStyle(Color.intent.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.intent.secondary.opacity(0.97), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast?.id)
        .allowsHitTesting(false)
    }
}

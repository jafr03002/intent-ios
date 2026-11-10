import IntentDesign
import SwiftUI

/// The tab shell: Home / Program / Start / Nutrition / You, each tab its own
/// NavigationStack. Start toggles the workout picker overlay (owned by the Log feature).
/// While a workout session runs, Start becomes the live resume button, and the logger
/// (Log feature's `WorkoutLauncher`) opens in place of the tab content with the
/// Program tab lit, as /log does on the web.
///
/// The bar is laid out *below* the content (a VStack), not hung on it with
/// `.safeAreaInset`: that inset never reached the scroll views inside the tabs'
/// NavigationStacks, so bottom buttons (onboarding's Continue, docks, the last row of
/// a page) ended up under the bar. A real frame boundary can't be missed.
struct MainTabView: View {
    @State private var tab: IntentTabBar.Tab
    @State private var showStart = false
    @State private var launcher: WorkoutLauncher
    @State private var hideTabBar = false

    init(initialTab: IntentTabBar.Tab = .home, startOpen: Bool = false, launcher: WorkoutLauncher? = nil) {
        _tab = State(initialValue: initialTab)
        _showStart = State(initialValue: startOpen)
        _launcher = State(initialValue: launcher ?? WorkoutLauncher())
    }

    var body: some View {
        let live = launcher.active != nil
        VStack(spacing: 0) {
            ZStack {
                if let route = launcher.route {
                    NavigationStack { LogScreen(request: route.request, debugShowCalibrationFinish: route.debugShowCalibrationFinish) }
                        .id(route.id)
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if showStart {
                    StartWorkoutOverlay(isPresented: $showStart)
                }
            }
            if !hideTabBar {
                IntentTabBar(
                    selection: showStart ? nil : (launcher.route != nil ? .program : tab),
                    startTitle: live ? " " : (showStart ? "Close" : "Start"),
                    startSystemImage: live ? "dumbbell.fill" : (showStart ? "xmark" : "play.fill"),
                    onSelect: { tab = $0; showStart = false; launcher.closeLog() },
                    onStart: { launcher.handleStart(pickerOpen: $showStart) }
                )
                .overlay { LiveStartDiscOverlay(launcher: launcher) { launcher.handleStart(pickerOpen: $showStart) } }
            }
        }
        .background(Color.intent.background.ignoresSafeArea())
        .onPreferenceChange(HidesTabBarKey.self) { hideTabBar = $0 }
        .workoutLauncherChrome(launcher, selectTab: { tab = $0; showStart = false })
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home: NavigationStack { DashboardScreen() }
        case .program: NavigationStack { ProgramScreen() }
        case .nutrition: NavigationStack { NutritionScreen() }
        case .you: NavigationStack { SettingsScreen() }
        }
    }
}

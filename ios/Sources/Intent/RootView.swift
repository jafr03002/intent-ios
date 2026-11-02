import SwiftUI

struct RootView: View {
    let screen: DebugScreen

    var body: some View {
        switch screen {
        case .home: AppRootView()

        case .dashboard: MainTabView(initialTab: .home)
        case .program: MainTabView(initialTab: .program)
        case .nutrition: MainTabView(initialTab: .nutrition)
        case .settings: MainTabView(initialTab: .you)
        case .start: MainTabView(initialTab: .home, startOpen: true)
        case .dashboardMiddle, .dashboardBottom, .dashboardDay, .dashboardIndependent, .dashboardIndependentBottom,
             .dashboardIndependentEdit, .dashboardCalibration, .dashboardCalibrationIntro, .dashboardCalibrationReview,
             .dashboardPrecalibration, .dashboardNoProgram:
            MainTabView(initialTab: .home)

        case .log: LogDebugHost(variant: .fresh)
        case .logMidsession: LogDebugHost(variant: .midsession)
        case .logCalibration: LogDebugHost(variant: .calibration)
        case .logCalibrationFinish: LogDebugHost(variant: .calibrationFinish)
        case .logEmpty: LogDebugHost(variant: .empty)
        case .briefing: LogDebugHost(variant: .briefing)
        case .startLive: LogDebugHost(variant: .startLive)
        case .programDay: NavigationStack { ProgramScreen(debug: .day) }
        case .programEditor: NavigationStack { ProgramScreen(debug: .editor) }
        case .programEditorChecklist: NavigationStack { ProgramScreen(debug: .editorChecklist) }
        case .programLibrary: NavigationStack { ProgramScreen(debug: .library) }
        case .programNew: NavigationStack { ProgramScreen(debug: .newProgram) }
        case .programGenerating: NavigationStack { ProgramScreen(debug: .generating) }
        case .programDeck: NavigationStack { ProgramScreen(debug: .deck(page: 1)) }
        case .programJourney: NavigationStack { ProgramScreen(debug: .deck(page: 2)) }
        case .programFeedback: NavigationStack { ProgramScreen(debug: .feedback) }

        case .log: NavigationStack { LogScreen() }
        case .calendar: NavigationStack { CalendarScreen() }
        case .progress: NavigationStack { ProgressScreen() }
        case .checkin: NavigationStack { CheckinScreen() }
        case .onboarding, .onboardingGoal, .onboardingGoalWeight, .onboardingDays, .onboardingRest,
             .onboardingEquipment, .onboardingDetails, .onboardingMuscles, .onboardingTargets, .onboardingReview,
             .onboardingReviewIndependent, .onboardingGenerating, .onboardingDeck, .onboardingDeckProgram,
             .onboardingDeckJourney, .onboardingDeckVolume, .onboardingDeckSessions, .onboardingDeckHappy,
             .onboardingTweak, .onboardingCommit, .onboardingCommitOther:
            OnboardingScreen(debug: screen.rawValue)

        case .calendarDay: NavigationStack { CalendarScreen(debug: .openLatest) }
        case .calendarDelete: NavigationStack { CalendarScreen(debug: .deleteConfirm) }
        case .calendarPrev: NavigationStack { CalendarScreen(debug: .previousMonth) }
        case .progressStrength: NavigationStack { ProgressScreen(debug: .strength) }
        case .progressWeeks: NavigationStack { ProgressScreen(debug: .weeks) }
        case .progressBottom: NavigationStack { ProgressScreen(debug: .bottom) }

        case .checkinStep2: NavigationStack { CheckinScreen(debug: .step2) }
        case .checkinSessions: NavigationStack { CheckinScreen(debug: .sessions) }
        case .checkinMissed: NavigationStack { CheckinScreen(debug: .missed) }
        case .checkinText: NavigationStack { CheckinScreen(debug: .text) }
        case .checkinResult: NavigationStack { CheckinScreen(debug: .result) }
        case .checkinLocked: NavigationStack { CheckinScreen(debug: .locked) }
        // [nutrition] / [settings] (standalone: the tab shell takes no debug state)
        case .nutritionOpen: NavigationStack { NutritionScreen(debug: .open) }
        case .settingsColors: NavigationStack { SettingsScreen(debug: .colors) }
        case .settingsBottom: NavigationStack { SettingsScreen(debug: .bottom) }
        case .settingsDelete: NavigationStack { SettingsScreen(debug: .deleteConfirm) }
        case .settingsMode: NavigationStack { SettingsScreen(debug: .modeConfirm) }

        case .styleguide: StyleguideView(part: .tokens)
        case .styleguideComponents: StyleguideView(part: .components)
        case .styleguideLists: StyleguideView(part: .lists)
        case .api: ApiDebugView()
        case .signIn: SignInDebugView()
        }
    }
}

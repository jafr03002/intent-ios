import Foundation

/// Screens the simulator workflow can open directly:
/// `xcrun simctl launch <udid> com.jakobfreij.Intent -IntentScreen <rawValue> [-IntentMock]`.
/// Every feature screen gets a case so CI can screenshot it. Without -IntentScreen the
/// app starts the real flow (`home`).
enum DebugScreen: String, CaseIterable {
    /// The real app: sign-in gate → onboarding gate → tab shell.
    case home

    // [shell] tab shell opened on a given tab / with the Start picker open
    case dashboard
    case program
    case nutrition
    case settings
    case start
    case startLive = "start-live"

    // [program] deeper Program-tab states (standalone, no tab bar)
    case programDay = "program-day"
    case programEditor = "program-editor"
    case programEditorChecklist = "program-editor-checklist"
    case programLibrary = "program-library"
    case programNew = "program-new"
    case programGenerating = "program-generating"
    case programDeck = "program-deck"
    case programJourney = "program-journey"
    case programFeedback = "program-feedback"

    // [dashboard] Home tab variants (DashboardDebugOptions): scrolled, the day sheet,
    // and other fixture scenarios (mock mode) for Independent mode and calibration.
    case dashboardMiddle = "dashboard-middle"
    case dashboardBottom = "dashboard-bottom"
    case dashboardDay = "dashboard-day"
    case dashboardIndependent = "dashboard-independent"
    case dashboardIndependentBottom = "dashboard-independent-bottom"
    case dashboardIndependentEdit = "dashboard-independent-edit"
    case dashboardCalibration = "dashboard-calibration"
    case dashboardCalibrationIntro = "dashboard-calibration-intro"
    case dashboardCalibrationReview = "dashboard-calibration-review"
    case dashboardPrecalibration = "dashboard-precalibration"
    case dashboardNoProgram = "dashboard-noprogram"

    // [features] standalone screens
    case log
    case logMidsession = "log-midsession"
    case logCalibration = "log-calibration"
    case logCalibrationFinish = "log-calibration-finish"
    case logEmpty = "log-empty"
    case briefing = "calibration-briefing"
    case calendar
    case progress
    case checkin
    case onboarding

    // [calendar] / [progress] states worth seeing
    case calendarDay = "calendar-day"
    case calendarDelete = "calendar-delete"
    case calendarPrev = "calendar-prev"
    case progressStrength = "progress-strength"
    case progressWeeks = "progress-weeks"
    case progressBottom = "progress-bottom"

    // [checkin] weekly check-in states (pinned to the "checkin" fixture scenarios;
    // add -CheckinStep <step> to deep-link any step)
    case checkinStep2 = "checkin-step2"
    case checkinSessions = "checkin-sessions"
    case checkinMissed = "checkin-missed"
    case checkinText = "checkin-text"
    case checkinResult = "checkin-result"
    case checkinLocked = "checkin-locked"
    // [onboarding] steps and phases, with sample answers (read the `onboarding` scenario)
    case onboardingGoal = "onboarding-goal"
    case onboardingGoalWeight = "onboarding-goal-weight"
    case onboardingDays = "onboarding-days"
    case onboardingRest = "onboarding-rest"
    case onboardingEquipment = "onboarding-equipment"
    case onboardingDetails = "onboarding-details"
    case onboardingMuscles = "onboarding-muscles"
    case onboardingTargets = "onboarding-targets"
    case onboardingReview = "onboarding-review"
    case onboardingReviewIndependent = "onboarding-review-independent"
    case onboardingGenerating = "onboarding-generating"
    case onboardingDeck = "onboarding-deck"
    case onboardingDeckProgram = "onboarding-deck-program"
    case onboardingDeckJourney = "onboarding-deck-journey"
    case onboardingDeckVolume = "onboarding-deck-volume"
    case onboardingDeckSessions = "onboarding-deck-sessions"
    case onboardingDeckHappy = "onboarding-deck-happy"
    case onboardingTweak = "onboarding-tweak"
    case onboardingCommit = "onboarding-commit"
    case onboardingCommitOther = "onboarding-commit-other"
    // [nutrition] / [settings] states worth seeing
    case nutritionOpen = "nutrition-open"
    case settingsColors = "settings-colors"
    case settingsBottom = "settings-bottom"
    case settingsDelete = "settings-delete"
    case settingsMode = "settings-mode"

    // [design] Sessions styleguide, split so each part fits one screenshot.
    case styleguide
    case styleguideComponents = "styleguide-components"
    case styleguideLists = "styleguide-lists"

    // [api] / [auth] diagnostics
    case api
    case signIn

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> DebugScreen {
        guard let flag = arguments.firstIndex(of: "-IntentScreen"),
              arguments.indices.contains(flag + 1) else { return .home }
        let name = arguments[flag + 1]
        guard let screen = DebugScreen(rawValue: name) else {
            appLog.error("Unknown -IntentScreen '\(name, privacy: .public)', falling back to home")
            return .home
        }
        return screen
    }
}

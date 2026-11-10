import Foundation
import SwiftUI

/// Where a debug variant opens the dashboard scrolled to.
enum DashboardAnchor: String {
    case top, targets, checkin, bottom

    var id: String { "dashboard-anchor-\(rawValue)" }
    var unitPoint: UnitPoint {
        switch self {
        case .top: .top
        case .targets, .checkin: .top
        case .bottom: .bottom
        }
    }
}

/// What the `-IntentScreen dashboard-*` variants change, so CI can screenshot every
/// state in one run: a fixture scenario (mock mode only), a scroll position, the day
/// sheet open, the targets editor open, the walkthrough's second page. Inert for the
/// real app (no variant -> all defaults).
struct DashboardDebugOptions {
    var scenario: String?
    var scrollAnchor: DashboardAnchor?
    var openTodaySheet = false
    var editTargets = false
    var walkthroughStep = 0

    static func fromLaunchArguments() -> DashboardDebugOptions {
        var o = DashboardDebugOptions()
        switch DebugScreen.fromLaunchArguments() {
        case .dashboardMiddle: o.scrollAnchor = .checkin
        case .dashboardBottom: o.scrollAnchor = .bottom
        case .dashboardDay: o.openTodaySheet = true
        case .dashboardIndependent: o.scenario = "independent"
        case .dashboardIndependentBottom: o.scenario = "independent"; o.scrollAnchor = .bottom
        case .dashboardIndependentEdit: o.scenario = "independent"; o.editTargets = true; o.scrollAnchor = .targets
        case .dashboardCalibration: o.scenario = "dashboard-calibration"
        case .dashboardCalibrationIntro: o.scenario = "dashboard-calibration-intro"
        case .dashboardCalibrationReview: o.scenario = "dashboard-calibration-intro"; o.walkthroughStep = 1
        case .dashboardPrecalibration: o.scenario = "dashboard-precalibration"
        case .dashboardNoProgram: o.scenario = "dashboard-noprogram"
        default: break
        }
        return o
    }
}

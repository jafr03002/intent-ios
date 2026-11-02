import Foundation
import Testing
@testable import IntentCore

// Hand-written tests for the weekly check-in (pages/checkin.tsx), the dashboard's
// check-in banner (pages/dashboard.tsx) and useAiJob's timing. That logic lives in
// React components and hooks, which the parity fixture generator can't run headless.

private let stockholm = TimeZone(identifier: "Europe/Stockholm")!
private let day: TimeInterval = 86_400

private func iso(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
}

private func row(_ phase: String?, _ generated: Date, ai: Bool = true, start: String? = nil) -> PhaseRow {
    PhaseRow(shortTermPhase: phase, weekInPhase: 1, generatedAt: iso(generated), aiGenerated: ai, startDate: start)
}

@Suite("Check-in flow (checkin.tsx)")
struct CheckinFlowTests {
    @Test func twelveStepsOnAFullWeekThirteenOnAShortOne() {
        let full = CheckinFlow.steps(loggedSessions: 4, plannedSessions: 4)
        #expect(full.count == 12)
        #expect(!full.contains(.missedReason))
        let short = CheckinFlow.steps(loggedSessions: 3, plannedSessions: 4)
        #expect(short.count == 13)
        #expect(short[5] == .missedReason)
        #expect(short[4] == .sessions)
        // Adherence loading or unavailable: no missed step.
        #expect(CheckinFlow.steps(loggedSessions: nil, plannedSessions: nil) == full)
        #expect(full.first == .energy && full.last == .notes)
    }

    @Test func clampKeepsTheStepInRange() {
        #expect(CheckinFlow.clampedStep(12, count: 12) == 11)
        #expect(CheckinFlow.clampedStep(3, count: 12) == 3)
    }

    @Test func requiredAnswersGateContinue() {
        var a = CheckinAnswers()
        #expect(!CheckinFlow.canAdvance(.energy, a))
        #expect(!CheckinFlow.canAdvance(.sleep, a))
        #expect(!CheckinFlow.canAdvance(.soreness, a))
        #expect(!CheckinFlow.canAdvance(.missedReason, a))
        #expect(!CheckinFlow.canAdvance(.hunger, a))
        #expect(!CheckinFlow.canAdvance(.offDay, a))
        for free in [CheckinStep.sleepDecline, .sessions, .exerciseIssues, .digestion, .wentWell, .didntGoWell, .notes] {
            #expect(CheckinFlow.canAdvance(free, a))
        }
        a.energy = 1; a.sleep = 5; a.soreness = "low"; a.missedReason = "time"; a.hungerAppetite = 3
        a.offDayDeviation = false // "No" is an answer
        for step in CheckinStep.allCases { #expect(CheckinFlow.canAdvance(step, a)) }
    }

    @Test func copy() {
        #expect(CheckinFlow.missedReasonTitle(missingDayLabels: ["Lower B"]) == "What happened with Lower B?")
        #expect(CheckinFlow.missedReasonTitle(missingDayLabels: ["Upper A", "Lower B"])
                == "What happened with the sessions you didn't log?")
        #expect(CheckinFlow.extraSessionsLine(0) == nil)
        #expect(CheckinFlow.extraSessionsLine(1) == "Plus 1 extra session beyond your program days.")
        #expect(CheckinFlow.extraSessionsLine(2) == "Plus 2 extra sessions beyond your program days.")
        #expect(CheckinFlow.missedReasons.map(\.value) == ["forgot_to_log", "time", "fatigue", "injury", "other"])
        #expect(CheckinFlow.nullIfEmpty("") == nil)
        #expect(CheckinFlow.nullIfEmpty(" ") == " ")
    }
}

@Suite("Check-in banner (dashboard.tsx)")
struct CheckinBannerTests {
    let now = Date(timeIntervalSince1970: 1_793_000_000) // Nov 2026

    func show(_ programs: [PhaseRow], latest: Date?, independent: Bool = false, hasProgram: Bool = true,
              onboarding: Date? = nil) -> Bool {
        CheckinBanner.shouldShow(isIndependent: independent, isLoading: false, hasCurrentProgram: hasProgram,
                                 programs: programs, latestCheckinAt: latest.map(iso),
                                 onboardingCompletedAt: onboarding.map(iso), now: now, timeZone: stockholm)
    }

    @Test func aiModeOnlyAndNeedsAProgram() {
        let p = [row("bulk", now - 30 * day)]
        #expect(show(p, latest: now - 8 * day))
        #expect(!show(p, latest: now - 8 * day, independent: true))
        #expect(!show(p, latest: now - 8 * day, hasProgram: false))
        #expect(!CheckinBanner.shouldShow(isIndependent: false, isLoading: true, hasCurrentProgram: true, programs: p,
                                          latestCheckinAt: nil, onboardingCompletedAt: nil, now: now))
    }

    @Test func sevenDaysAfterTheLastCheckin() {
        let p = [row("bulk", now - 30 * day)]
        #expect(!show(p, latest: now - 6.9 * day))
        #expect(show(p, latest: now - 7 * day))
    }

    @Test func closedDuringCalibrationAndAWeekAfterTheReview() {
        let calib = row("calibration", now - 10 * day)
        #expect(!show([calib], latest: nil))
        // Review 3 days ago: closed. 7+ days ago: open and first after review, regardless of history.
        #expect(!show([row("bulk", now - 3 * day), calib], latest: nil))
        #expect(show([row("bulk", now - 7.5 * day), row("calibration", now - 15 * day)], latest: nil))
        // A check-in since the review: back to the 7-day rhythm.
        #expect(!show([row("bulk", now - 20 * day), row("calibration", now - 28 * day)], latest: now - 2 * day))
    }

    @Test func firstEverCheckinSixDaysAfterTrainingStarted() {
        // A pre-calibration program (no calibration row): the original day-6 nudge.
        let p = [row("bulk", now - 3 * day)]
        #expect(!show(p, latest: nil, onboarding: now - 5 * day))
        #expect(show(p, latest: nil, onboarding: now - 6.5 * day))
        #expect(!show(p, latest: nil)) // no start date at all
        // Manual rows are a different lineage and never count.
        #expect(!show([row("bulk", now - 3 * day, ai: false)], latest: nil))
    }
}

@Suite("AI job polling (useAiJob.ts)")
struct AiJobPolicyTests {
    @Test func resumeWindow() {
        let now = Date()
        #expect(AiJobPolicy.pollInterval == .milliseconds(2500))
        #expect(AiJobPolicy.isResumable(startedAt: now - 6 * 60, now: now))
        #expect(!AiJobPolicy.isResumable(startedAt: now - 6.6 * 60, now: now))
        #expect(!AiJobPolicy.hasGivenUp(startedAt: now - 6.4 * 60, now: now))
        #expect(AiJobPolicy.hasGivenUp(startedAt: now - 7 * 60, now: now))
    }
}

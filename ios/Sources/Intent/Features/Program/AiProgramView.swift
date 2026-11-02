import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// The AI Coach program page (pages/program/ai.tsx). Reads the AI lineage only.
/// Generation and feedback regeneration run as polled jobs; a job left running by an
/// earlier visit reopens straight onto the loading screen.
struct AiProgramView: View {
    @Environment(AppServices.self) private var services

    let profile: ProgramAPI.Profile?
    var debug: ProgramDebug = .none
    var reloadProfile: () async -> Void

    private enum Phase { case idle, generating, presentation }

    @State private var program: Program?
    @State private var loading = true
    @State private var durationStats: [DayDurationStat] = []
    @State private var phase: Phase = .idle
    @State private var freshProgram: Program?
    @State private var regenerateCount = 0
    @State private var poller: ProgramGenerationPoller?
    @State private var updateProfileFailed = false
    @State private var openSettings = false
    @State private var openOnboarding = false
    @State private var didStart = false

    private var isAiModeActive: Bool { profile?.isIndependent != true }
    private var aiProfileReady: Bool { profile?.aiProfileReady ?? false }

    var body: some View {
        content
            .navigationDestination(isPresented: $openSettings) { SettingsScreen() }
            .navigationDestination(isPresented: $openOnboarding) { OnboardingScreen() }
            .task { await start() }
            .onDisappear { poller?.abandon() }
    }

    @ViewBuilder private var content: some View {
        if phase == .generating {
            ProgramGeneratingView()
        } else if phase == .presentation, let freshProgram {
            ProgramPresentationDeck(
                program: freshProgram,
                goal: profile?.goal ?? "",
                weightUnit: profile?.weightUnit,
                name: profile?.name,
                priorityMuscles: profile?.priorityMuscles ?? [],
                onSatisfied: {
                    // The web goes to /dashboard; the tab shell can't switch tabs from
                    // here, so this returns to the program page.
                    phase = .idle
                },
                onSubmitFeedback: { feedback in Task { await regenerate(feedback) } },
                isSubmitting: poller?.isPending ?? false,
                showRegenerateNudge: regenerateCount >= 3,
                error: (poller?.isError ?? false) || updateProfileFailed,
                initialPage: debugDeckPage,
                initiallyTweaking: debug == .feedback
            )
        } else if loading {
            IntentPage { ProgramLoading() }
        } else if let program {
            ScrollViewReader { proxy in
                IntentPage {
                    if !isAiModeActive {
                        inactiveNotice
                    }
                    ProgramWeekView(
                        program: program,
                        canStartWorkout: isAiModeActive,
                        badge: IntentBadge("AI Coach", tint: .accent),
                        durationStats: durationStats,
                        onProgramChanged: { Task { await loadProgram() } },
                        initialDay: debug == .day ? 1 : 0
                    )
                }
                .onAppear {
                    if debug == .day {
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            proxy.scrollTo("program-roster", anchor: .bottom)
                        }
                    }
                }
            }
        } else {
            IntentPage { emptyState }
        }
    }

    private var debugDeckPage: Int {
        switch debug {
        case .deck(let page): page
        case .feedback: ProgramPresentation.pages.count - 1
        default: 0
        }
    }

    private var inactiveNotice: some View {
        Button { openSettings = true } label: {
            ProgramNotice {
                Text("This is your AI Coach program, kept exactly as it was. You're training in Independent mode right now, so workouts log against your own program. ")
                    + Text("Switch mode in Settings").foregroundColor(Color.intent.foreground).underline()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var emptyState: some View {
        if !aiProfileReady {
            ProgramCenteredMessage(
                title: "A few things to set before AI can build your program",
                message: "We don't have your goal, experience, or equipment yet - the AI coach needs those to write a program."
            ) {
                Button("Set up AI coaching") { openOnboarding = true }
                    .buttonStyle(.intentPrimary)
                    .fixedSize()
            }
        } else if isAiModeActive {
            ProgramCenteredMessage(
                title: "No AI program yet",
                message: "Your AI coach has what it needs - generate your first program to get started."
            ) {
                VStack(spacing: 16) {
                    Button("Generate my program") { handleGenerate() }
                        .buttonStyle(.intentPrimary)
                        .fixedSize()
                    if poller?.isError == true {
                        Text("Something went wrong generating your program. Try again.")
                            .font(.intent(14, .regular))
                            .foregroundStyle(Color.intent.destructive)
                    }
                }
            }
        } else {
            ProgramCenteredMessage(
                title: "No AI program yet",
                message: "You're in Independent mode. Switch to AI Coach mode in Settings to have a program generated for you - your own program stays untouched either way."
            ) {
                Button("Open Settings") { openSettings = true }
                    .buttonStyle(.intentOutline)
                    .fixedSize()
            }
        }
    }

    // MARK: Loading + generation

    private func start() async {
        guard !didStart else { return }
        didStart = true
        let poller = ProgramGenerationPoller.programGeneration(services.api)
        self.poller = poller
        if debug == .generating {
            phase = .generating
            return
        }
        if poller.resumable {
            phase = .generating
            Task { await follow { try await poller.resume() } }
        }
        let api = services.api
        async let stats = ProgramAPI.durationStats(api)
        await loadProgram()
        durationStats = await stats
        if case .deck = debug, let program { freshProgram = program; phase = .presentation }
        if debug == .feedback, let program { freshProgram = program; phase = .presentation }
    }

    private func loadProgram() async {
        do {
            program = try await ProgramAPI.currentProgram(services.api, lineage: .ai)
        } catch {
            appLog.error("program: AI program load failed: \(String(describing: error), privacy: .public)")
        }
        loading = false
    }

    private func follow(_ job: @escaping () async throws -> Program) async {
        do {
            let result = try await job()
            await loadProgram()
            freshProgram = result
            phase = .presentation
        } catch is ProgramGenerationPoller.Abandoned {
            return
        } catch {
            phase = .idle
        }
    }

    private func handleGenerate() {
        guard let poller else { return }
        phase = .generating
        Task { await follow { try await poller.run(nil) } }
    }

    private func regenerate(_ feedback: ProgramFeedbackDraft) async {
        guard let poller else { return }
        phase = .generating
        regenerateCount += 1
        updateProfileFailed = false
        do {
            // A new day count is saved first: the generator reads trainingDays from
            // the profile, not from the feedback.
            if let days = feedback.trainingDays {
                do {
                    try await ProgramAPI.updateProfile(services.api, .init(trainingDays: days))
                } catch {
                    updateProfileFailed = true
                    throw error
                }
                await reloadProfile()
            }
            let result = try await poller.run(ProgramAPI.feedbackInput(feedback))
            await loadProgram()
            freshProgram = result
        } catch is ProgramGenerationPoller.Abandoned {
            return
        } catch {
            // Keep the previous program on screen; the deck's banner reports it.
        }
        phase = .presentation
    }
}

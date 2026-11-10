import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// The build-your-own program page (pages/program/my.tsx). Reads and writes the manual
/// lineage only; building and editing are allowed in either mode because the lineages
/// are separate.
struct MyProgramView: View {
    @Environment(AppServices.self) private var services

    let profile: ProgramAPI.Profile?
    var debug: ProgramDebug = .none

    @State private var program: Program?
    @State private var loading = true
    @State private var building = false
    @State private var editing = false
    @State private var durationStats: [DayDurationStat] = []
    @State private var colorOverrides: [String: String] = [:]
    @State private var openSettings = false
    @State private var didStart = false

    private var isIndependent: Bool { profile?.isIndependent == true }
    private var userId: String? { profile?.userId }

    var body: some View {
        ScrollViewReader { proxy in
            IntentPage { content }
                .onChange(of: loading) { _, isLoading in
                    guard !isLoading else { return }
                    scrollForDebug(proxy)
                }
        }
        .navigationDestination(isPresented: $openSettings) { SettingsScreen() }
        .task { await start() }
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgramLoading()
        } else if let program, !(debug == .newProgram) {
            if editing {
                titleBlock("Edit program", "Change days, exercises, sets and muscles. Past sessions stay as they were.")
                ProgramBuilderView(
                    editProgram: program,
                    userId: userId,
                    colorOverrides: colorOverrides,
                    onSaved: { saved in self.program = saved; editing = false },
                    onCancel: { editing = false },
                    debugOpenLibrary: debug == .library
                )
            } else {
                if !isIndependent {
                    Button { openSettings = true } label: {
                        ProgramNotice {
                            Text("This is your own program, kept exactly as you built it. You're training in AI Coach mode right now, so workouts log against the AI program. ")
                                + Text("Switch mode in Settings").foregroundColor(Color.intent.foreground).underline()
                        }
                    }
                    .buttonStyle(.plain)
                }
                ProgramWeekView(
                    program: program,
                    canStartWorkout: isIndependent,
                    badge: IntentBadge("Custom"),
                    durationStats: durationStats,
                    onEdit: { editing = true },
                    onProgramChanged: { Task { await loadProgram() } },
                    initialDay: debug == .day ? 1 : 0
                )
            }
        } else {
            titleBlock("My Program", "Build your own training program.")
            if building {
                ProgramBuilderView(
                    editProgram: nil,
                    userId: userId,
                    colorOverrides: colorOverrides,
                    onSaved: { saved in self.program = saved; building = false },
                    onCancel: { building = false }
                )
            } else {
                ProgramCenteredMessage(
                    title: "No program yet",
                    message: "Create your first training program with your own days and exercises."
                ) {
                    Button("Create your program") { building = true }
                        .buttonStyle(.intentPrimary)
                        .fixedSize()
                        .accessibilityIdentifier("button-create-program")
                }
            }
        }
    }

    private func titleBlock(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .intentText(.screenTitle)
                .foregroundStyle(Color.intent.foreground)
            Text(subtitle)
                .intentText(.body)
                .foregroundStyle(Color.intent.mutedForeground)
        }
    }

    private func start() async {
        guard !didStart else { return }
        didStart = true
        let api = services.api
        async let stats = ProgramAPI.durationStats(api)
        async let colors = ProgramAPI.calendarColors(api)
        await loadProgram()
        durationStats = await stats
        colorOverrides = await colors

        switch debug {
        case .editor, .editorChecklist, .library: editing = program != nil
        case .newProgram: building = true
        default: autoResumeDraft()
        }
        loading = false
    }

    private func loadProgram() async {
        do {
            program = try await ProgramAPI.currentProgram(services.api, lineage: .manual)
        } catch {
            appLog.error("program: manual program load failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Reopens the builder mid-edit when a draft holds changes the program doesn't
    /// already have (not merely when a draft exists). Checked once per mount.
    private func autoResumeDraft() {
        guard let userId else { return }
        if let program {
            let draft = ProgramDraftStore.load(userId: userId, programId: program.id)
            if ProgramBuilder.draftHasChanges(draft, programName: program.programName, days: program.days) { editing = true }
        } else {
            let draft = ProgramDraftStore.load(userId: userId, programId: nil)
            if ProgramBuilder.draftHasChanges(draft, programName: nil, days: nil) { building = true }
        }
    }

    private func scrollForDebug(_ proxy: ScrollViewProxy) {
        let target: String? = switch debug {
        case .day: "program-roster"
        case .editorChecklist: "builder-day-0"
        default: nil
        }
        guard let target else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

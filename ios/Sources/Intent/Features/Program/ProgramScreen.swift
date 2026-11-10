import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// The Program tab. Like the web's `/program` redirect (pages/program/index.tsx) it
/// lands on the active training mode's page: the AI Coach program, or "My program"
/// (the manual lineage) in Independent mode. The two pages read separate lineages
/// (`?lineage=ai|manual`), so nothing done on one can change the other.
struct ProgramScreen: View {
    @Environment(AppServices.self) private var services

    private let debug: ProgramDebug

    init() { debug = .none }

    /// For DebugScreen variants (CI screenshots of deeper states).
    init(debug: ProgramDebug) { self.debug = debug }

    @State private var profile: ProgramAPI.Profile?
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                IntentPage { ProgramLoading() }
            } else if debug.forcesMyProgram || profile?.isIndependent == true {
                MyProgramView(profile: profile, debug: debug)
            } else {
                AiProgramView(profile: profile, debug: debug, reloadProfile: { await loadProfile() })
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !loaded else { return }
            await loadProfile()
            loaded = true
        }
    }

    private func loadProfile() async {
        do {
            profile = try await ProgramAPI.profile(services.api)
        } catch {
            appLog.error("program: profile load failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Deeper program states the CI simulator can open directly (see DebugScreen).
enum ProgramDebug: Sendable, Equatable {
    case none
    /// The second training day picked, scrolled to its roster.
    case day
    /// My program in edit mode.
    case editor
    /// The editor scrolled down to the first day's checklist items.
    case editorChecklist
    /// The editor with the exercise library sheet open.
    case library
    /// The builder creating a new manual program.
    case newProgram
    /// The "Building your program" screen.
    case generating
    /// The post-generation deck, on a page (1 = program highlights, 2 = journey).
    case deck(page: Int)
    /// The deck's last page with the feedback sheet open.
    case feedback

    var forcesMyProgram: Bool {
        switch self {
        case .editor, .editorChecklist, .library, .newProgram: true
        default: false
        }
    }
}

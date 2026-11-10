import IntentCore
import IntentDesign
import SwiftUI

/// The tab bar's workout picker (web: components/StartWorkoutMenu.tsx): what Start
/// opens when no session is running. A plain `bg-card` grouped list that springs up
/// out of the Start disc over a scrim that stops at the tab bar, so the bar stays
/// sharp and Start - now Close - stays usable. It lists the program's days and
/// nothing else; picking one is the deliberate press that starts a session.
struct StartWorkoutOverlay: View {
    @Binding var isPresented: Bool
    @Environment(AppServices.self) private var services
    @Environment(WorkoutLauncher.self) private var launcher: WorkoutLauncher?
    @State private var fallbackProgram: Program?
    @State private var shown = false

    private var program: Program? { launcher?.program ?? fallbackProgram }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(shown ? 0.6 : 0)
                .ignoresSafeArea(edges: .top)
                .onTapGesture { close() }
                .accessibilityHidden(true)
            if let program {
                panel(program)
                    .scaleEffect(shown ? 1 : 0.9, anchor: .bottom)
                    .offset(y: shown ? 0 : 12)
                    .opacity(shown ? 1 : 0)
            }
        }
        .onAppear { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2)) { shown = true } }
        .task {
            // Standalone (no launcher in the environment): fetch the program ourselves.
            guard launcher == nil, fallbackProgram == nil else { return }
            fallbackProgram = try? await LogAPI.program(services.api.api)
        }
    }

    private func close() { isPresented = false }

    private func panel(_ program: Program) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Start a workout")
                .font(.intent(11, .medium)).tracking(1.32).textCase(.uppercase)
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(program.days, id: \.dayNumber) { day in
                        row(LogScreenRules.startMenuRow(day))
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 288)
        .background(Color.intent.card)
        .clipShape(RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous))
        .padding(.horizontal, 16)
        // 6.25rem above the screen bottom on the web = 36pt above the bar's top edge.
        .padding(.bottom, 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Start a workout")
        .accessibilityAddTraits(.isModal)
    }

    private func row(_ row: StartMenuRow) -> some View {
        Button {
            isPresented = false
            launcher?.startDay(row.dayNumber)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).intentText(.rowTitle).foregroundStyle(Color.intent.foreground).lineLimit(1)
                Text(row.subtitle).intentText(.caption).foregroundStyle(Color.intent.mutedForeground).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13)
            .padding(.trailing, 20)
            .overlay(alignment: .top) { IntentDivider() }
            .padding(.leading, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(StartRowStyle())
    }

    private struct StartRowStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.background(configuration.isPressed ? Color.intent.secondary : Color.clear)
        }
    }
}

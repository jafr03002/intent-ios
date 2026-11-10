#if canImport(SwiftUI) // Apple-only module; compiles empty on Linux so `swift test` works in WSL
import SwiftUI

/// The mobile tab bar from components/layout.tsx (option A): a black blurred bar
/// with a hairline on top, the active tab white and the rest muted, and Start as a
/// raised white disc with a black play icon in the middle.
///
/// Visuals only: it reports taps, the app owns navigation. Lay it out below the
/// content (MainTabView uses a VStack): it is `tabBarHeight + startDiscRise` tall, and
/// its background runs on down through the home-indicator inset.
public struct IntentTabBar: View {
    public enum Tab: String, CaseIterable, Sendable {
        case home, program, nutrition, you

        public var title: String {
            switch self {
            case .home: "Home"
            case .program: "Program"
            case .nutrition: "Nutrition"
            case .you: "You"
            }
        }

        /// SF Symbol stand-ins for the web's lucide House, Dumbbell, Salad, CircleUser.
        public var systemImage: String {
            switch self {
            case .home: "house"
            case .program: "dumbbell"
            case .nutrition: "carrot"
            case .you: "person.crop.circle"
            }
        }
    }

    private let selection: Tab?
    private let startTitle: String
    private let startSystemImage: String
    private let onSelect: (Tab) -> Void
    private let onStart: () -> Void

    /// - Parameters:
    ///   - selection: the lit tab, or nil when none is (e.g. a full-screen flow).
    ///   - startTitle / startSystemImage: "Start" + play by default; "Close" + xmark
    ///     while the workout picker is open.
    public init(
        selection: Tab?,
        startTitle: String = "Start",
        startSystemImage: String = "play.fill",
        onSelect: @escaping (Tab) -> Void = { _ in },
        onStart: @escaping () -> Void = {}
    ) {
        self.selection = selection
        self.startTitle = startTitle
        self.startSystemImage = startSystemImage
        self.onSelect = onSelect
        self.onStart = onStart
    }

    public var body: some View {
        // The view is `tabBarHeight + startDiscRise` tall: the bar row at the bottom,
        // and above it a clear strip the raised Start disc pokes into (the web's
        // `pb-[5.5rem]` on <main> vs the 4rem bar). Only the disc's column is
        // tappable up there; elsewhere the strip passes touches through.
        HStack(alignment: .bottom, spacing: 0) {
            tab(.home)
            tab(.program)
            startButton
            tab(.nutrition)
            tab(.you)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: 448)
        .frame(height: IntentMetrics.tabBarHeight + IntentMetrics.startDiscRise)
        .frame(maxWidth: .infinity)
        .background {
            // `bg-sidebar/80 backdrop-blur-xl`: black at 80% over a blur, down
            // through the home-indicator inset.
            // The `border-t` hairline sits behind the Start disc, as on the web.
            ZStack(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial)
                Color.intent.sidebar.opacity(0.8)
                Rectangle()
                    .fill(Color.intent.sidebarBorder)
                    .frame(height: IntentMetrics.hairline)
            }
            .padding(.top, IntentMetrics.startDiscRise)
            .ignoresSafeArea(edges: .bottom)
        }
        .environment(\.colorScheme, .dark)
    }

    private func tab(_ tab: Tab) -> some View {
        let active = tab == selection
        return Button { onSelect(tab) } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 21, weight: active ? .regular : .light))
                    .frame(height: 24)
                Text(tab.title)
                    .intentText(.tabLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: IntentMetrics.tabBarHeight)
            .foregroundStyle(active ? Color.intent.foreground : Color.intent.mutedForeground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var startButton: some View {
        Button(action: onStart) {
            VStack(spacing: 4) {
                Image(systemName: startSystemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .offset(x: startSystemImage == "play.fill" ? 1 : 0)
                    .foregroundStyle(Color.black)
                    .frame(width: IntentMetrics.startDisc, height: IntentMetrics.startDisc)
                    .background(Circle().fill(Color.white))
                    // `ring-4 ring-black`: a black collar that cuts the disc out of the bar's hairline.
                    .background(Circle().fill(Color.black).padding(-4))
                    .padding(.top, -IntentMetrics.startDiscRise)
                Text(startTitle)
                    .intentText(.tabLabel)
                    .foregroundStyle(Color.intent.foreground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: IntentMetrics.tabBarHeight)
            // The hit area is the whole column, rise included: the disc pokes above
            // the bar row, and its top half used to sit outside the button and
            // swallow taps (the "middle button does nothing" bug).
            .frame(height: IntentMetrics.tabBarHeight + IntentMetrics.startDiscRise, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(StartPressStyle())
        .accessibilityLabel(startTitle == "Start" ? "Start a workout" : startTitle)
    }

    private struct StartPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
#endif

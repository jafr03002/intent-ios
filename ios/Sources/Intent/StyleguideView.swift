import SwiftUI
import IntentDesign

/// [design] The Sessions styleguide: every IntentDesign token, type style and
/// component, split into parts that each fit one simulator screenshot
/// (`-IntentScreen styleguide | styleguide-components | styleguide-lists`).
struct StyleguideView: View {
    enum Part { case tokens, components, lists }

    let part: Part

    init(part: Part) {
        self.part = part
        // Moves to IntentApp.init when the phase-0 branches merge; harmless twice.
        IntentDesign.registerFonts()
    }

    var body: some View {
        IntentPage {
            switch part {
            case .tokens: TokensPart()
            case .components: ComponentsPart()
            case .lists: ListsPart()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IntentTabBar(selection: part == .lists ? .you : .program)
        }
    }
}

// MARK: - Tokens + type

private struct TokensPart: View {
    private let swatches: [IntentColorToken] = [
        .background, .card, .secondary, .accent, .border,
        .input, .foreground, .mutedForeground, .primary, .sessionsCyan,
        .destructive, .chart1, .chart2, .chart3, .chart4,
    ]

    var body: some View {
        IntentPageHeader("Styleguide") {
            Text("Sessions · tokens")
            IntentBadge(IntentDesign.fontsAvailable ? "Inter" : "No Inter", tint: IntentDesign.fontsAvailable ? .accent : .neutral)
        }

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
            ForEach(swatches, id: \.self) { token in
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(token.color)
                        .frame(height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.intent.border, lineWidth: token == .background ? IntentMetrics.hairline : 0)
                        )
                    Text(token.rawValue)
                        .font(.intent(9))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            sample("Screen title 34", .screenTitle)
            sample("Section title 21", .sectionTitle)
            sample("Hero title 24", .heroTitle)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                sample("128.5", .statNumber)
                sample("Kg · stat label", .caps, muted: true)
            }
            sample("Row title 15 · Bench press", .rowTitle)
            sample("Body 14 relaxed. Contrast comes from weight and size, not a second face.", .body, muted: true)
            sample("Caption 12.5 · 3 sets × 8 reps", .caption, muted: true)
            sample("Eyebrow tracked caps", .eyebrow, muted: true)
            HStack(spacing: 14) {
                weightSample("Light", .light)
                weightSample("Regular", .regular)
                weightSample("Medium", .medium)
                weightSample("Semi", .semibold)
                weightSample("Bold", .bold)
            }
            // Inter vs the system face, to eyeball that the bundled font loaded.
            HStack(spacing: 16) {
                Text("Rag 1Il0").font(.intent(21, .light))
                Text("Rag 1Il0").font(.system(size: 21, weight: .light))
                    .foregroundStyle(Color.intent.mutedForeground)
                Text("Inter | SF").intentText(.caps).foregroundStyle(Color.intent.mutedForeground)
            }
        }
    }

    private func sample(_ text: String, _ style: IntentTextStyle, muted: Bool = false) -> some View {
        Text(text)
            .intentText(style)
            .foregroundStyle(muted ? Color.intent.mutedForeground : Color.intent.foreground)
            .lineLimit(2)
    }

    private func weightSample(_ name: String, _ weight: IntentFontWeight) -> some View {
        Text(name).font(.intent(14, weight))
    }
}

// MARK: - Components

private struct ComponentsPart: View {
    @State private var goal = "build"
    @State private var tab = "Week"

    var body: some View {
        IntentPageHeader("Upper Lower") {
            Text("Week 3")
            IntentBadge("AI Coach", tint: .accent)
            IntentBadge("Custom")
        } trailing: {
            IntentIconButton("Progress", systemImage: "chart.xyaxis.line") {}
            IntentIconButton("Edit program", systemImage: "pencil") {}
        }

        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(["Week", "Upper A", "Lower A", "Upper B", "Lower B"], id: \.self) { name in
                    IntentPill(name, isSelected: tab == name) { tab = name }
                }
            }
        }
        .scrollIndicators(.hidden)

        VStack(spacing: IntentSpacing.stack) {
            IntentOptionCard("Build muscle", subtitle: "Add size with steady volume", isSelected: goal == "build") { goal = "build" }
            IntentOptionCard("Lose fat", subtitle: "Keep strength while you cut", isSelected: goal == "cut") { goal = "cut" }
        }

        IntentCard {
            Text("Card · bg-card rounded-3xl")
                .intentText(.rowTitle)
            Text("Black → card → secondary. No borders.")
                .intentText(.caption)
                .foregroundStyle(Color.intent.mutedForeground)
                .padding(.top, 4)
            HStack(spacing: 0) {
                stat("4", "Days")
                IntentDivider(.vertical).frame(height: 40)
                stat("22", "Sets")
                IntentDivider(.vertical).frame(height: 40)
                stat("55", "Min")
            }
            .padding(.top, 14)
        }

        HStack(spacing: 10) {
            Button("Back") {}.buttonStyle(.intentOutline)
            Button("Continue") {}.buttonStyle(.intentPrimary)
        }
        HStack(spacing: 10) {
            Button("Secondary") {}.buttonStyle(.intentSecondary)
            Button("Disabled") {}.buttonStyle(.intentPrimary).disabled(true)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).intentText(.statNumber)
            Text(label).intentText(.caps).foregroundStyle(Color.intent.mutedForeground)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Lists

private struct ListsPart: View {
    var body: some View {
        IntentPageHeader("Settings")

        IntentGroupedSection("Exercises") {
            IntentGroupedRow("Bench press", subtitle: "Chest · Triceps", value: "4 × 6–8")
            IntentGroupedRow("Barbell row", subtitle: "Back · Biceps", value: "4 × 8")
            IntentGroupedRow("Overhead press", subtitle: "Shoulders", value: "3 × 8–10")
        }

        IntentGroupedSection("Profile", footer: "Grouped like iOS Settings: hairlines start at the text inset.") {
            IntentGroupedRow("Name", value: "Jakob", showsChevron: true, action: {})
            IntentGroupedRow("Bodyweight", value: "82.4 kg", showsChevron: true, action: {})
            IntentGroupedRow("Units", value: "Metric", showsChevron: true, action: {})
            IntentGroupedRow("Sign out", isDestructive: true, action: {})
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("Hairline divider").intentText(.eyebrow).foregroundStyle(Color.intent.mutedForeground)
            IntentDivider()
        }
    }
}

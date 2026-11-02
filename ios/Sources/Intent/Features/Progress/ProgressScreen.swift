import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI

/// Debug states CI screenshots (see DebugScreen).
enum ProgressDebug {
    case none
    /// Bench press picked in the strength card.
    case strength
    /// Volume card on "All weeks", scrolled to it.
    case weeks
    /// Scrolled to the personal records.
    case bottom
}

/// /progress (port of pages/progress.tsx): strength (max weight per tracked
/// exercise), bodyweight with the goal-weight line, sets per muscle (this week ranked,
/// or weekly totals) and personal records. Metric-card pattern: caps label, big light
/// number, muted delta, minimal axis-less chart.
struct ProgressScreen: View {
    @Environment(AppServices.self) private var services
    @State private var data = ProgressData()
    @State private var selectedExercise = ""
    @State private var volumeView: VolumeView = .latest
    private let debug: ProgressDebug

    enum VolumeView { case latest, weeks }

    init(debug: ProgressDebug = .none) {
        self.debug = debug
    }

    var body: some View {
        ScrollViewReader { proxy in
            IntentPage {
                header
                strengthSection.id("strength")
                bodyweightSection.id("bodyweight")
                volumeSection.id("volume")
                recordsSection.id("records")
            }
            .task {
                await data.load(services.api)
                await applyDebug(proxy)
            }
        }
        .task(id: selectedExercise) {
            await data.loadStrength(selectedExercise, client: services.api)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        let recent = ProgressMath.recentPrCount(data.records, now: Date())
        return VStack(alignment: .leading, spacing: 8) {
            Text("Progress").intentText(.screenTitle)
            ProgressFlowRow {
                Text("Strength, volume, bodyweight and records")
                    .font(.intent(13.5))
                    .foregroundStyle(Color.intent.mutedForeground)
                if recent > 0 {
                    IntentBadge("\(recent) new PR\(recent > 1 ? "s" : "") this week", tint: .accent)
                }
            }
        }
    }

    // MARK: Strength

    private var strengthSection: some View {
        let points = data.strength.enumerated().map { ProgressLinePoint(index: $0.offset, date: $0.element.date, value: $0.element.maxWeight) }
        let first = data.strength.first, last = data.strength.last
        return section("Strength") {
            VStack(alignment: .leading, spacing: 0) {
                exercisePicker.padding(.bottom, 20)
                if selectedExercise.isEmpty {
                    cardMessage("Select an exercise to see strength progress")
                } else if data.strengthLoading && data.strength.isEmpty {
                    cardMessage("Loading...")
                } else if let first, let last {
                    capsLabel("Max weight")
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        bigNumber(ProgressMath.fmt(last.maxWeight), unit: data.weightUnit)
                        Spacer(minLength: 0)
                        if data.strength.count > 1 {
                            sinceText(ProgressMath.signed(last.maxWeight - first.maxWeight), since: first.date)
                        }
                    }
                    .padding(.top, 6)
                    ProgressAreaChart(points: points, bounds: ProgressMath.strengthBounds(data.strength.map(\.maxWeight)),
                                      unit: data.weightUnit, seriesName: "Max weight")
                        .padding(.top, 16)
                    dateRange(first.date, last.date).padding(.top, 8)
                } else {
                    cardMessage("No data yet")
                }
            }
        }
    }

    private var exercisePicker: some View {
        Menu {
            Button("Select exercise...") { selectedExercise = "" }
            ForEach(data.trackedExercises, id: \.self) { name in
                Button(name) { selectedExercise = name }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedExercise.isEmpty ? "Select exercise..." : selectedExercise)
                    .font(.intent(14))
                    .foregroundStyle(Color.intent.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color.intent.mutedForeground)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .frame(height: 48)
            .background(Capsule().fill(Color.intent.secondary))
            .contentShape(Capsule())
        }
        .accessibilityLabel("Exercise")
        .accessibilityValue(selectedExercise.isEmpty ? "None" : selectedExercise)
        .accessibilityIdentifier("select-exercise")
    }

    // MARK: Bodyweight

    private var bodyweightSection: some View {
        let first = data.bodyweight.first, last = data.bodyweight.last
        let points = data.bodyweight.enumerated().map { ProgressLinePoint(index: $0.offset, date: $0.element.date, value: $0.element.weight) }
        return section("Bodyweight") {
            if data.bodyweightLoading {
                cardMessage("Loading...")
            } else if let first, let last {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            capsLabel("Current")
                            bigNumber(ProgressMath.fmt(last.weight), unit: data.weightUnit)
                            if data.bodyweight.count > 1 {
                                sinceText(ProgressMath.signed(last.weight - first.weight), since: first.date)
                            }
                        }
                        Spacer(minLength: 0)
                        if let goal = data.goalWeight {
                            VStack(alignment: .trailing, spacing: 6) {
                                Text("Goal").intentText(.caps).foregroundStyle(Color.intent.sessionsCyan)
                                bigNumber(ProgressMath.fmt(goal), unit: data.weightUnit, muted: true)
                                Text(ProgressMath.goalLine(current: last.weight, goalWeight: goal, unit: data.weightUnit))
                                    .font(.intent(12.5))
                                    .foregroundStyle(Color.intent.mutedForeground)
                                    .lineLimit(1)
                            }
                        }
                    }
                    ProgressAreaChart(points: points,
                                      bounds: ProgressMath.bodyweightBounds(data.bodyweight.map(\.weight), goalWeight: data.goalWeight),
                                      unit: data.weightUnit, seriesName: "Bodyweight", showsDots: false,
                                      goal: data.goalWeight, height: 140, fillOpacity: 0.16)
                        .padding(.top, 16)
                    dateRange(first.date, last.date).padding(.top, 8)
                }
            } else {
                cardMessage("Log today's bodyweight from the dashboard to start tracking")
            }
        }
    }

    // MARK: Volume

    private var volumeSection: some View {
        let weeks = data.muscleWeeks
        let latest = weeks.last
        let prior = weeks.count > 1 ? weeks[weeks.count - 2] : nil
        let ranked = ProgressMath.rankedMuscles(latest: latest, prior: prior)
        let topSets = ranked.first?.sets ?? 0
        let latestTotal = ProgressMath.weekTotal(latest)
        return section("Volume by muscle", meta: "Sets per week") {
            if let latest {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            volumePill("Week \(latest.week)", view: .latest)
                            volumePill("All weeks", view: .weeks)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.bottom, 20)

                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            capsLabel("Total sets")
                            bigNumber("\(latestTotal)", unit: "sets")
                        }
                        Spacer(minLength: 0)
                        if let prior {
                            let change = latestTotal - ProgressMath.weekTotal(prior)
                            (Text(ProgressMath.signed(Double(change)))
                                .font(.intent(12.5, .medium))
                                .foregroundColor(change > 0 ? Color.intent.sessionsCyan : Color.intent.foreground)
                             + Text(" vs week \(prior.week)"))
                                .font(.intent(12.5))
                                .foregroundStyle(Color.intent.mutedForeground)
                                .lineLimit(1)
                        }
                    }
                    .padding(.bottom, 20)

                    if volumeView == .latest {
                        VStack(spacing: 12) {
                            ForEach(Array(ranked.enumerated()), id: \.element.key) { i, m in
                                muscleRow(m, lead: i < ProgressMath.leadMuscles, topSets: topSets, hasPrior: prior != nil)
                            }
                        }
                    } else {
                        ProgressWeeklyBars(totals: ProgressMath.weeklyTotals(weeks))
                    }
                }
            } else {
                cardMessage("No data yet")
            }
        }
    }

    private func volumePill(_ title: String, view: VolumeView) -> some View {
        let on = volumeView == view
        return Button { volumeView = view } label: {
            Text(title)
                .font(.intent(14, on ? .medium : .regular))
                .foregroundStyle(on ? Color.black : Color.intent.mutedForeground)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(on ? Color.white : Color.intent.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func muscleRow(_ m: ProgressMath.RankedMuscle, lead: Bool, topSets: Int, hasPrior: Bool) -> some View {
        HStack(spacing: 12) {
            Text(m.label)
                .font(.intent(13))
                .lineLimit(1)
                .frame(width: 88, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.intent.secondary)
                    Capsule()
                        .fill(lead ? Color.intent.foreground : Color.intent.mutedForeground.opacity(0.5))
                        .frame(width: topSets > 0 ? geo.size.width * CGFloat(m.sets) / CGFloat(topSets) : 0)
                }
            }
            .frame(height: 6)
            Text("\(m.sets)")
                .font(.intent(13))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
            Text(hasPrior ? ProgressMath.signed(Double(m.change)) : "")
                .font(.intent(11.5))
                .monospacedDigit()
                .foregroundStyle(m.change > 0 ? Color.intent.sessionsCyan : Color.intent.mutedForeground)
                .lineLimit(1)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Records

    private var recordsSection: some View {
        let count = data.records.count
        let meta: String? = count > 0 ? "\(count) lift\(count > 1 ? "s" : "")" : nil
        let now = Date()
        return VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Personal records", meta: meta)
            if data.records.isEmpty {
                cardMessage("Beat a set from an earlier session to earn your first personal record")
                    .intentSurface(radius: IntentRadius.groupedList)
            } else {
                let rows = ProgressMath.sortedRecords(data.records)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, pr in
                        recordRow(pr, recent: ProgressMath.isRecent(pr.date, now: now), last: i == rows.count - 1)
                    }
                }
                .intentSurface(radius: IntentRadius.groupedList)
            }
        }
    }

    private func recordRow(_ pr: PersonalRecord, recent: Bool, last: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(recent ? Color.intent.sessionsCyan : Color.intent.mutedForeground)
                .frame(width: 36, height: 36)
                .background(Circle().fill(recent ? Color.intent.sessionsCyan.opacity(0.1) : Color.intent.secondary))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(pr.exercise).intentText(.rowTitle).lineLimit(1)
                        if recent {
                            Text("New")
                                .font(.intent(10, .medium))
                                .tracking(1)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.intent.sessionsCyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.intent.sessionsCyan.opacity(0.1)))
                                .fixedSize()
                        }
                    }
                    Text(ProgressMath.shortDateWithYear(pr.date))
                        .intentText(.caption)
                        .foregroundStyle(Color.intent.mutedForeground)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                (Text("\(JSNumber.string(pr.maxWeight)) \(data.weightUnit)").foregroundColor(Color.intent.foreground)
                 + Text(pr.reps.map { $0 != 0 ? " × \($0)" : "" } ?? ""))
                    .font(.intent(15))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 14)
            .padding(.trailing, 20)
            .overlay(alignment: .bottom) { if !last { IntentDivider() } }
        }
        .padding(.leading, 20)
        .accessibilityElement(children: .combine)
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, meta: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(title, meta: meta)
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .intentSurface(radius: IntentRadius.groupedList)
        }
    }

    private func sectionTitle(_ title: String, meta: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).intentText(.sectionTitle)
            Spacer(minLength: 0)
            if let meta {
                Text(meta).font(.intent(12.5)).foregroundStyle(Color.intent.mutedForeground).lineLimit(1)
            }
        }
        .padding(.bottom, 12)
    }

    private func cardMessage(_ text: String) -> some View {
        Text(text)
            .font(.intent(14))
            .foregroundStyle(Color.intent.mutedForeground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 128)
    }

    private func capsLabel(_ text: String) -> some View {
        Text(text).intentText(.caps).foregroundStyle(Color.intent.mutedForeground)
    }

    private func bigNumber(_ value: String, unit: String, muted: Bool = false) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(value)
                .font(.intent(28, .light))
                .tracking(-0.56)
                .foregroundStyle(muted ? Color.intent.mutedForeground : Color.intent.foreground)
            Text(unit).font(.intent(14)).foregroundStyle(Color.intent.mutedForeground)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func sinceText(_ delta: String, since date: String) -> some View {
        (Text("\(delta) \(data.weightUnit)").font(.intent(12.5, .medium)).foregroundColor(Color.intent.foreground)
         + Text(" since \(ProgressMath.shortDate(date))"))
            .font(.intent(12.5))
            .foregroundStyle(Color.intent.mutedForeground)
            .lineLimit(1)
    }

    private func dateRange(_ from: String, _ to: String) -> some View {
        HStack {
            Text(ProgressMath.shortDate(from))
            Spacer()
            Text(ProgressMath.shortDate(to))
        }
        .intentText(.caps)
        .foregroundStyle(Color.intent.mutedForeground)
    }

    private func applyDebug(_ proxy: ScrollViewProxy) async {
        switch debug {
        case .none: break
        case .strength:
            selectedExercise = data.trackedExercises.first { $0 == "Barbell Bench Press" } ?? data.trackedExercises.first ?? ""
        case .weeks:
            volumeView = .weeks
            try? await Task.sleep(for: .milliseconds(300))
            proxy.scrollTo("volume", anchor: .top)
        case .bottom:
            try? await Task.sleep(for: .milliseconds(300))
            proxy.scrollTo("records", anchor: .bottom)
        }
    }
}

/// `String(n)` for a weight (80 not 80.0), without reaching into IntentCore internals.
private enum JSNumber {
    static func string(_ x: Double) -> String {
        x == x.rounded() && abs(x) < 1e15 ? String(Int(x)) : String(x)
    }
}

/// Wraps its children onto new lines when they don't fit (the web's `flex-wrap`). Also used by the calendar header.
struct ProgressFlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > 0 && x + size.width > bounds.width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

import IntentCore
import IntentDesign
import SwiftUI

/// The month as seven columns of days (port of components/calendar/MonthGrid.tsx).
///
/// Phases are continuous grey bands behind the days, named where they start with the
/// phase colour only in a small dot. A trained day is a solid white disc, a planned
/// one is outlined, and today is a small white dot under its number. The selection
/// is a glass lens that glides between days on a slightly underdamped spring and
/// magnifies the disc under it; a horizontal drag scrubs it along the week.
struct CalendarMonthGrid: View {
    let padding: Int
    let days: [CalendarMonth.Day]
    let selected: String
    /// Tap: select (if needed) and open.
    let onTap: (String) -> Void
    /// Scrub: select only.
    let onSelect: (String) -> Void

    static let rowHeight: CGFloat = 62
    static let rowGap: CGFloat = 4
    static let disc: CGFloat = 36
    static let discTop: CGFloat = 6
    static let lens: CGFloat = 48

    @Namespace private var lensSpace
    @State private var pressing = false

    var body: some View {
        let rows = CalendarMonth.rows(padding: padding, days: days)
        VStack(spacing: Self.rowGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                row(cells)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Days of the month")
    }

    private func row(_ cells: [CalendarMonth.Day?]) -> some View {
        GeometryReader { geo in
            let colW = geo.size.width / 7
            ZStack(alignment: .topLeading) {
                CalendarPhaseBands(runs: CalendarMonth.bandRuns(cells), columnWidth: colW, height: Self.rowHeight)
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        if let day = cells[c] {
                            cell(day)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(scrub(cells: cells, columnWidth: colW))
        }
        .frame(height: Self.rowHeight)
    }

    private func cell(_ day: CalendarMonth.Day) -> some View {
        let isSelected = day.date == selected
        return ZStack(alignment: .top) {
            disc(day, selected: isSelected)
                .scaleEffect(isSelected ? (pressing ? 1.16 : 1.1) : 1)
                .padding(.top, Self.discTop)
            if day.isToday {
                Circle().fill(Color.white).frame(width: 4, height: 4)
                    .padding(.top, Self.discTop + Self.disc + 3)
            }
            if isSelected {
                CalendarLens()
                    .frame(width: Self.lens, height: Self.lens)
                    .scaleEffect(pressing ? 1.14 : 1)
                    .padding(.top, Self.discTop + Self.disc / 2 - Self.lens / 2)
                    .matchedGeometryEffect(id: "lens", in: lensSpace)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { onTap(day.date) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func disc(_ day: CalendarMonth.Day, selected: Bool) -> some View {
        let emphasise = (selected || day.isToday) && !day.trained
        let weight: IntentFontWeight = day.trained ? .medium : (emphasise ? .semibold : .regular)
        let text = Text("\(day.day)")
            .font(.intent(15, weight))
            .monospacedDigit()
            .frame(width: Self.disc, height: Self.disc)
        if day.trained {
            text.foregroundStyle(Color.black).background(Circle().fill(Color.white))
        } else if day.planned {
            text.foregroundStyle(Color.intent.foreground)
                .overlay(Circle().strokeBorder(Color.intent.mutedForeground.opacity(0.42), lineWidth: 1))
        } else if day.isPast {
            text.foregroundStyle(emphasise ? Color.intent.foreground : Color.intent.mutedForeground)
        } else {
            text.foregroundStyle(emphasise ? Color.intent.foreground : Color.intent.foreground.opacity(0.85))
        }
    }

    /// A horizontal drag scrubs the lens along this week; vertical drags still scroll.
    private func scrub(cells: [CalendarMonth.Day?], columnWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if !pressing { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { pressing = true } }
                let c = min(6, max(0, Int(value.location.x / max(columnWidth, 1))))
                // Snap to the nearest real day in the row.
                let target = cells[c] ?? nearest(cells, to: c)
                if let target, target.date != selected { onSelect(target.date) }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pressing = false }
            }
    }

    private func nearest(_ cells: [CalendarMonth.Day?], to c: Int) -> CalendarMonth.Day? {
        cells.enumerated().compactMap { i, d in d.map { (abs(i - c), $0) } }.min { $0.0 < $1.0 }?.1
    }
}

/// The selected-day lens: clear glass with an edge highlight and a soft shadow, as
/// the web's liquid-glass lens (no rainbow fringe, no glow).
struct CalendarLens: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.05))
            Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            // Top specular edge.
            Circle()
                .trim(from: 0.58, to: 0.92)
                .stroke(Color.white.opacity(0.38), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .padding(1.5)
            // Faint lower inner light.
            Circle()
                .fill(RadialGradient(colors: [.clear, Color.white.opacity(0.10)], center: .init(x: 0.5, y: 0.35),
                                     startRadius: 14, endRadius: 26))
        }
        .shadow(color: .black.opacity(0.75), radius: 11, x: 0, y: 10)
        .allowsHitTesting(false)
    }
}

/// One rounded grey band per run of same-phase days in a week row; ends are fully
/// round where the phase starts or ends and softly rounded where it wraps.
struct CalendarPhaseBands: View {
    let runs: [CalendarMonth.BandRun]
    let columnWidth: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(runs, id: \.from) { run in
                let l: CGFloat = run.start ? 22 : 8
                let r: CGFloat = run.end ? 22 : 8
                UnevenRoundedRectangle(topLeadingRadius: l, bottomLeadingRadius: l, bottomTrailingRadius: r,
                                       topTrailingRadius: r, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .frame(width: CGFloat(run.to - run.from + 1) * columnWidth - 4, height: height - 2)
                    .offset(x: CGFloat(run.from) * columnWidth + 2, y: 1)
            }
            // The name may run past a short band to the end of the week.
            ForEach(runs.filter(\.named), id: \.from) { run in
                HStack(spacing: 4) {
                    Circle().fill(CalendarPaint.phase(run.phase)).frame(width: 5, height: 5)
                    Text(PhaseColors.label(run.phase))
                        .font(.intent(8.5, .semibold))
                        .tracking(0.85)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.intent.foreground.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: CGFloat(7 - run.from) * columnWidth - 14, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: CGFloat(run.from) * columnWidth + 10, y: height - 4 - 9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

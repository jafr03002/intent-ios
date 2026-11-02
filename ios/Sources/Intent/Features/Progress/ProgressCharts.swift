import Charts
import IntentCore
import IntentDesign
import SwiftUI

// The progress page's minimal, axis-less charts (Swift Charts). Sessions keeps them
// monochrome: a white 2pt line over a faint white fill, cyan only for the goal.
// Touch shows a crosshair and a value callout.

/// One point of an over-time line, x = its position (the web's categorical x-axis).
struct ProgressLinePoint: Identifiable {
    let index: Int
    let date: String
    let value: Double
    var id: Int { index }
}

/// The strength / bodyweight area chart.
struct ProgressAreaChart: View {
    let points: [ProgressLinePoint]
    let bounds: ProgressMath.Bounds?
    let unit: String
    let seriesName: String
    var showsDots = true
    var goal: Double?
    var height: CGFloat = 130
    var fillOpacity: Double = 0.18

    @State private var selected: Int?

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Session", p.index),
                         yStart: .value(seriesName, bounds?.lower ?? 0),
                         yEnd: .value(seriesName, p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Color.intent.foreground.opacity(fillOpacity), Color.intent.foreground.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Session", p.index), y: .value(seriesName, p.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.intent.foreground)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if showsDots {
                    PointMark(x: .value("Session", p.index), y: .value(seriesName, p.value))
                        .symbol {
                            Circle()
                                .strokeBorder(Color.intent.foreground, lineWidth: 1.5)
                                .background(Circle().fill(Color.intent.card))
                                .frame(width: 6, height: 6)
                        }
                }
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Color.intent.sessionsCyan)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
            if let p = selectedPoint {
                RuleMark(x: .value("Session", p.index))
                    .foregroundStyle(Color.intent.border)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ProgressCallout(title: ProgressMath.shortDate(p.date),
                                        value: "\(ProgressMath.fmt(p.value)) \(unit)", label: seriesName)
                    }
                PointMark(x: .value("Session", p.index), y: .value(seriesName, p.value))
                    .symbol { Circle().fill(Color.intent.foreground).frame(width: 9, height: 9) }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: xDomain, range: .plotDimension(padding: 6))
        .chartYScale(domain: (bounds?.lower ?? 0)...max(bounds?.upper ?? 1, (bounds?.lower ?? 0) + 1))
        .chartXSelection(value: $selected)
        .frame(height: height)
        .accessibilityLabel(seriesName)
        .accessibilityValue(accessibilitySummary)
    }

    private var xDomain: ClosedRange<Int> {
        points.count > 1 ? 0...(points.count - 1) : -1...1
    }

    private var selectedPoint: ProgressLinePoint? {
        guard let selected, !points.isEmpty else { return nil }
        return points[min(points.count - 1, max(0, selected))]
    }

    private var accessibilitySummary: String {
        points.map { "\(ProgressMath.shortDate($0.date)): \(ProgressMath.fmt($0.value)) \(unit)" }.joined(separator: ", ")
    }
}

/// The volume card's "All weeks" bars: this week white, the rest grey.
struct ProgressWeeklyBars: View {
    let totals: [ProgressMath.WeekTotal]
    @State private var selected: String?

    var body: some View {
        let lastWeek = totals.last?.week
        Chart {
            ForEach(totals, id: \.week) { w in
                BarMark(x: .value("Week", "Wk \(w.week)"), y: .value("Sets", w.sets),
                        width: .fixed(min(34, 220 / CGFloat(max(totals.count, 1)))))
                    .cornerRadius(10)
                    .foregroundStyle(w.week == lastWeek ? Color.intent.foreground : Color.intent.mutedForeground.opacity(0.35))
                    .annotation(position: .top, spacing: 4) {
                        if selected == "Wk \(w.week)" {
                            ProgressCallout(title: "Week \(w.week)", value: "\(w.sets) sets", label: "Total")
                        }
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.intent(10.5))
                    .foregroundStyle(Color.intent.mutedForeground)
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $selected)
        .frame(height: 170)
        .accessibilityLabel("Total sets per week")
        .accessibilityValue(totals.map { "Week \($0.week): \($0.sets) sets" }.joined(separator: ", "))
    }
}

/// The hover tooltip (`tooltipStyle`): card surface, hairline border, 16pt corners.
struct ProgressCallout: View {
    let title: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.intent(12)).foregroundStyle(Color.intent.mutedForeground)
            HStack(spacing: 4) {
                Text(label).foregroundStyle(Color.intent.mutedForeground)
                Text(value).foregroundStyle(Color.intent.foreground)
            }
            .font(.intent(12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.intent.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.intent.border, lineWidth: 1))
        .fixedSize()
    }
}

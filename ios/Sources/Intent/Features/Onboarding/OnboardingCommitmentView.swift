import IntentCore
import IntentDesign
import SwiftUI

/// "Start day" (CommitmentScreen.tsx): Today / Tomorrow / next Monday as one tap,
/// "Another day" opens a month grid for the rest of the 30-day window.
struct OnboardingCommitmentView: View {
    let program: IntentCore.Program
    let isSaving: Bool
    let error: String?
    let onConfirm: (Date) -> Void

    private let today: Date
    private let rangeEnd: Date
    private let picks: [StartDayPicker.QuickPick]
    private let calendar: Calendar

    @State private var selected: Date
    @State private var pickingOther: Bool
    @State private var viewMonth: Date

    init(program: IntentCore.Program, isSaving: Bool, error: String?, initialPickingOther: Bool = false,
         now: Date = Date(), onConfirm: @escaping (Date) -> Void) {
        self.program = program; self.isSaving = isSaving; self.error = error; self.onConfirm = onConfirm
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        calendar = cal
        let start = cal.startOfDay(for: now)
        today = start
        rangeEnd = StartDayPicker.rangeEnd(today: start)
        picks = StartDayPicker.quickPicks(today: start)
        _selected = State(initialValue: start)
        _pickingOther = State(initialValue: initialPickingOther)
        _viewMonth = State(initialValue: cal.date(from: cal.dateComponents([.year, .month], from: start))!)
    }

    private var isQuickPick: Bool { picks.contains { calendar.isDate($0.date, inSameDayAs: selected) } }
    private var firstMonth: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: today))! }
    private var lastMonth: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: rangeEnd))! }

    var body: some View {
        ZStack(alignment: .top) {
            Color.intent.background.ignoresSafeArea()
            OnboardingLetterWash(bookend: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingPageHead(title: "Start day", parts: headParts)
                    VStack(spacing: 10) {
                        ForEach(picks, id: \.key) { p in
                            optionCard(title: p.title,
                                       subtitle: p.key == "monday" ? "\(Self.format(p.date, "d MMM")) · the start of a fresh week"
                                                                   : Self.format(p.date, "EEEE d MMM"),
                                       selected: calendar.isDate(selected, inSameDayAs: p.date), trailing: false) {
                                selected = p.date
                                pickingOther = false
                            }
                        }
                        optionCard(title: "Another day",
                                   subtitle: isQuickPick ? "Up to 30 days out" : Self.format(selected, "EEEE d MMM"),
                                   selected: !isQuickPick, trailing: true) {
                            withAnimation(.easeOut(duration: 0.2)) { pickingOther.toggle() }
                        }
                    }
                    .padding(.top, 28)
                    if pickingOther { monthPicker.padding(.top, 24).transition(.opacity) }
                    if let error {
                        Text(error).font(.intent(13)).foregroundStyle(Color.intent.destructive).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Color.intent.foreground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingLetterDock(
                label: calendar.isDate(selected, inSameDayAs: today) ? "Start today" : "Start \(Self.format(selected, "EEE d MMM"))",
                disabled: isSaving,
                onNext: { onConfirm(selected) })
        }
    }

    private var headParts: [OnboardingSayPart] {
        if let first = program.days.first {
            return [.plain("Your first session is "), .fact(first.label), .plain(", "), .fact(first.focus.lowercased()), .plain(".")]
        }
        return [.plain("Pick the day you "), .fact("start training"), .plain(".")]
    }

    private func optionCard(title: String, subtitle: String, selected: Bool, trailing: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.intent(15))
                    Text(subtitle).font(.intent(12.5))
                        .foregroundStyle(selected ? Color.black.opacity(0.6) : Color.intent.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                } else if trailing {
                    Image(systemName: "chevron.right").font(.system(size: 13))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .rotationEffect(.degrees(pickingOther ? 90 : 0))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .foregroundStyle(selected ? Color.black : Color.intent.foreground)
            .background(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous)
                .fill(selected ? Color.white : Color.intent.card))
            .contentShape(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var monthPicker: some View {
        let canPrev = !calendar.isDate(viewMonth, equalTo: firstMonth, toGranularity: .month)
        let canNext = !calendar.isDate(viewMonth, equalTo: lastMonth, toGranularity: .month)
        let cells = StartDayPicker.monthCells(viewMonth)
        return VStack(spacing: 0) {
            HStack {
                Text(Self.format(viewMonth, "MMMM yyyy")).font(.intent(17, .light))
                Spacer()
                monthButton("chevron.left", label: "Previous month", enabled: canPrev) {
                    viewMonth = calendar.date(byAdding: .month, value: -1, to: viewMonth)!
                }
                monthButton("chevron.right", label: "Next month", enabled: canNext) {
                    viewMonth = calendar.date(byAdding: .month, value: 1, to: viewMonth)!
                }
            }
            .padding(.bottom, 12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(ProgramScheduleReader.weekdayLabels, id: \.self) { d in
                    Text(d).font(.intent(10.5)).tracking(0.6).textCase(.uppercase)
                        .foregroundStyle(Color.intent.mutedForeground).padding(.bottom, 4)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 48) }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let disabled = date < today || date > rangeEnd
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let isToday = calendar.isDate(date, inSameDayAs: today)
        return Button { selected = date } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.intent(15, isSelected && !disabled ? .regular : .light))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(disabled ? Color.intent.mutedForeground.opacity(0.3)
                                     : isSelected ? Color.black : Color.intent.foreground)
                    .background(Circle().fill(!disabled && isSelected ? Color.white : Color.clear))
                Circle().fill(isToday ? Color.white : Color.clear).frame(width: 4, height: 4)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(Self.format(date, "EEEE d MMMM"))
    }

    private func monthButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13)).frame(width: 32, height: 32)
                .foregroundStyle(Color.intent.mutedForeground)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    /// date-fns `format` patterns in English.
    static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

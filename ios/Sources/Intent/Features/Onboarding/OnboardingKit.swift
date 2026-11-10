import IntentDesign
import SwiftUI

// The pieces of lib/sessionsForm.ts and onboarding.tsx's helpers that IntentDesign
// doesn't already cover: a choice card with extra content, the chip with an
// "invalid" state, pill inputs, the kg/lbs toggle, the info notice, a wrapping
// row for chips, and the training-days slider. Onboarding-prefixed so nothing
// clashes with other features.

// MARK: Type

extension View {
    /// `TITLE_CLASS`
    func onboardingTitle() -> some View {
        intentText(.screenTitle).foregroundStyle(Color.intent.foreground).fixedSize(horizontal: false, vertical: true)
    }

    /// `LEDE_CLASS` (mt-2.5 mb-8)
    func onboardingLede() -> some View {
        intentText(.lede).foregroundStyle(Color.intent.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10).padding(.bottom, 32)
    }
}

/// `LABEL_CLASS`: 13pt foreground, ml-1 mb-2, with an optional muted "(optional)".
struct OnboardingLabel: View {
    let text: String
    var optional = false
    var body: some View {
        (Text(text).foregroundStyle(Color.intent.foreground)
         + Text(optional ? " (optional)" : "").foregroundStyle(Color.intent.mutedForeground))
            .font(.intent(13))
            .padding(.leading, 4).padding(.bottom, 8)
    }
}

/// `ERROR_TEXT_CLASS`
struct OnboardingErrorText: View {
    let text: String
    var body: some View {
        Text(text).font(.intent(13, .medium)).foregroundStyle(Color.intent.destructive)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 4).padding(.top, 8)
    }
}

// MARK: Choice card

/// `optionCardClass`: grey at rest, white with black text once picked; optional
/// icon disc above the title and extra content under the sub line.
struct OnboardingChoiceCard<Extra: View>: View {
    let title: String
    let sub: String
    let selected: Bool
    var systemImage: String?
    let action: () -> Void
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .light))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(selected ? Color.black.opacity(0.07) : Color.intent.secondary))
                        .padding(.bottom, 14)
                }
                Text(title).font(.intent(16, .medium))
                Text(sub)
                    .intentText(.optionSubtitle)
                    .foregroundStyle(selected ? Color.black.opacity(0.6) : Color.intent.mutedForeground)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .foregroundStyle(selected ? Color.black : Color.intent.foreground)
            .background(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous)
                .fill(selected ? Color.white : Color.intent.card))
            .contentShape(RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension OnboardingChoiceCard where Extra == EmptyView {
    init(title: String, sub: String, selected: Bool, systemImage: String? = nil, action: @escaping () -> Void) {
        self.init(title: title, sub: sub, selected: selected, systemImage: systemImage, action: action, extra: { EmptyView() })
    }
}

// MARK: Chips

/// `chipClass(selected, invalid)`. `onCard` steps unselected chips up to
/// `bg-secondary` for use on a `bg-card` sheet.
struct OnboardingChip: View {
    let title: String
    let selected: Bool
    var invalid = false
    var onCard = false
    var height: CGFloat?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.intent(14, selected || invalid ? .medium : .regular))
                .lineLimit(1)
                .padding(.horizontal, 17)
                .padding(.vertical, 10)
                .frame(maxWidth: height == nil ? nil : .infinity)
                .frame(height: height)
                .foregroundStyle(invalid ? Color.intent.destructive : selected ? Color.black : Color.intent.mutedForeground)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        if invalid { return Color.intent.destructive.opacity(0.15) }
        if selected { return .white }
        return onCard ? Color.intent.secondary : Color.intent.card
    }
}

/// `flex flex-wrap gap-2`.
struct OnboardingWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: Inputs

/// `inputClass`: a 52pt pill field on `bg-card` (or `fill`), a 1pt ring when invalid
/// or focused.
struct OnboardingPillField: View {
    let placeholder: String
    @Binding var text: String
    var invalid = false
    var keyboard: UIKeyboardType = .default
    var fill: Color = Color.intent.card
    var suffix: String?
    var maxLength: Int?
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.intent.mutedForeground.opacity(0.6)))
                .font(.intent(16))
                .foregroundStyle(Color.intent.foreground)
                .keyboardType(keyboard)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .frame(maxWidth: .infinity)
                .onChange(of: text) { _, value in
                    if let maxLength, value.count > maxLength { text = String(value.prefix(maxLength)) }
                }
            if let suffix {
                Text(suffix).font(.intent(14)).foregroundStyle(Color.intent.mutedForeground)
                    .lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: IntentMetrics.controlHeight)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(ring, lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { focused = true }
    }

    private var ring: Color {
        if invalid { return Color.intent.destructive }
        return focused ? Color.intent.foreground.opacity(0.4) : .clear
    }
}

/// kg / lbs (`UnitToggle`).
struct OnboardingUnitToggle: View {
    @Binding var unit: String
    var fill: Color = Color.intent.card
    var onChange: () -> Void = {}

    var body: some View {
        HStack(spacing: 2) {
            ForEach(["kg", "lbs"], id: \.self) { u in
                Button {
                    unit = u
                    onChange()
                } label: {
                    Text(u)
                        .font(.intent(13, unit == u ? .medium : .regular))
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity)
                        .foregroundStyle(unit == u ? Color.black : Color.intent.mutedForeground)
                        .background(Capsule().fill(unit == u ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(unit == u ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(height: IntentMetrics.controlHeight)
        .background(Capsule().fill(fill))
        .accessibilityLabel("Weight unit")
    }
}

/// The info notice (`Notice`): `rounded-[22px] bg-card`, info icon, 12.5pt muted.
struct OnboardingNotice: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").font(.system(size: 15, weight: .light)).padding(.top, 1)
            Text(text).intentText(.caption).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.intent.mutedForeground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: IntentRadius.notice, style: .continuous).fill(Color.intent.card))
    }
}

/// The 2-6 training-days slider (`.sessions-range`): a 4pt `accent` track and a
/// 28pt white thumb, snapping to whole days.
struct OnboardingDaySlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        GeometryReader { geo in
            let thumb: CGFloat = 28
            let span = CGFloat(range.upperBound - range.lowerBound)
            let fraction = CGFloat(value - range.lowerBound) / span
            ZStack(alignment: .leading) {
                Capsule().fill(Color.intent.accent).frame(height: 4)
                Circle().fill(Color.white).frame(width: thumb, height: thumb)
                    .offset(x: fraction * (geo.size.width - thumb))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = min(max((g.location.x - thumb / 2) / (geo.size.width - thumb), 0), 1)
                let next = range.lowerBound + Int((f * span).rounded())
                if next != value { value = next }
            })
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel("Training days per week")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// The grabber at the top of a bottom sheet (`h-[5px] w-[38px] bg-accent`).
struct OnboardingGrabber: View {
    var body: some View {
        Capsule().fill(Color.intent.accent).frame(width: 38, height: 5)
            .frame(maxWidth: .infinity).padding(.bottom, 20)
    }
}

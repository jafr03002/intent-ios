#if canImport(SwiftUI) // Apple-only module; compiles empty on Linux so `swift test` works in WSL
import SwiftUI

// The Sessions building blocks, as built on the web's /program page, onboarding
// (lib/sessionsForm.ts), Settings and the tab bar (components/layout.tsx). The web
// is a token set rather than a component zoo, so this stays small: surfaces,
// pills, one row type. No glows, no coloured shadows, no gradients.

// MARK: - Page frame

/// The page frame (`ProgramPageShell`): black canvas, `p-6` gutter, `space-y-6`
/// sections, scrolling.
public struct IntentPage<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IntentSpacing.section) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(IntentSpacing.gutter)
        }
        .scrollIndicators(.hidden)
        .background(Color.intent.background.ignoresSafeArea())
        .foregroundStyle(Color.intent.foreground)
    }
}

/// The plain /program-style header: a light 34pt title on the left, an optional
/// muted meta line (plus badge) under it, and round icon buttons on the right.
public struct IntentPageHeader<Meta: View, Trailing: View>: View {
    private let title: String
    private let meta: Meta
    private let trailing: Trailing

    public init(_ title: String, @ViewBuilder meta: () -> Meta, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.meta = meta()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .intentText(.screenTitle)
                    .foregroundStyle(Color.intent.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { meta }
                    .font(.intent(13.5))
                    .foregroundStyle(Color.intent.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { trailing }
        }
    }
}

public extension IntentPageHeader where Meta == EmptyView, Trailing == EmptyView {
    init(_ title: String) {
        self.init(title, meta: { EmptyView() }, trailing: { EmptyView() })
    }
}

public extension IntentPageHeader where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder meta: () -> Meta) {
        self.init(title, meta: meta, trailing: { EmptyView() })
    }
}

/// Section title ("Training days"): light 21pt, 12pt above its content.
public struct IntentSectionTitle: View {
    private let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title)
            .intentText(.sectionTitle)
            .foregroundStyle(Color.intent.foreground)
            .padding(.bottom, IntentSpacing.sectionTitle)
    }
}

// MARK: - Surfaces

public extension View {
    /// A Sessions surface: `bg-card rounded-3xl` (or any radius). No border, no shadow;
    /// depth comes from the step between greys.
    func intentSurface(_ color: Color = Color.intent.card, radius: CGFloat = IntentRadius.card) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A `bg-card rounded-3xl` card with the usual `px-5 py-[18px]` padding.
public struct IntentCard<Content: View>: View {
    private let radius: CGFloat
    private let padding: EdgeInsets
    private let content: Content

    public init(
        radius: CGFloat = IntentRadius.card,
        padding: EdgeInsets = EdgeInsets(top: IntentSpacing.optionVertical, leading: IntentSpacing.rowInset, bottom: IntentSpacing.optionVertical, trailing: IntentSpacing.rowInset),
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .intentSurface(radius: radius)
    }
}

/// A hairline (`border-border`, 1pt). Horizontal by default.
public struct IntentDivider: View {
    private let axis: Axis
    public init(_ axis: Axis = .horizontal) { self.axis = axis }
    public var body: some View {
        Rectangle()
            .fill(Color.intent.border)
            .frame(width: axis == .vertical ? IntentMetrics.hairline : nil,
                   height: axis == .horizontal ? IntentMetrics.hairline : nil)
    }
}

// MARK: - Buttons

/// White pill with black caps text (`PRIMARY_BUTTON_CLASS`). Disabled turns
/// `secondary` with muted text.
public struct IntentPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .intentText(.button)
            .lineLimit(1)
            .padding(.horizontal, 32)
            .frame(height: IntentMetrics.controlHeight)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isEnabled ? Color.intent.primaryForeground : Color.intent.mutedForeground)
            .background(
                Capsule().fill(isEnabled ? Color.intent.primary.opacity(configuration.isPressed ? 0.9 : 1) : Color.intent.secondary)
            )
            .contentShape(Capsule())
    }
}

/// Outlined pill (`OUTLINE_BUTTON_CLASS`): `border-foreground/90`, transparent,
/// fills `secondary` while pressed.
public struct IntentOutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .intentText(.buttonSecondary)
            .lineLimit(1)
            .padding(.horizontal, 24)
            .frame(height: IntentMetrics.controlHeight)
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color.intent.foreground)
            .background(Capsule().fill(configuration.isPressed ? Color.intent.secondary : Color.clear))
            .overlay(Capsule().strokeBorder(Color.intent.foreground.opacity(0.9), lineWidth: IntentMetrics.hairline))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// The quieter secondary pill: `bg-secondary`, hover/pressed `bg-accent`.
public struct IntentSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .intentText(.buttonSecondary)
            .lineLimit(1)
            .padding(.horizontal, 24)
            .frame(height: IntentMetrics.controlHeight)
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color.intent.secondaryForeground)
            .background(Capsule().fill(configuration.isPressed ? Color.intent.accent : Color.intent.secondary))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
    }
}

public extension ButtonStyle where Self == IntentPrimaryButtonStyle {
    /// White pill, black caps label.
    static var intentPrimary: IntentPrimaryButtonStyle { .init() }
}

public extension ButtonStyle where Self == IntentOutlineButtonStyle {
    /// Outlined pill (Back, secondary actions).
    static var intentOutline: IntentOutlineButtonStyle { .init() }
}

public extension ButtonStyle where Self == IntentSecondaryButtonStyle {
    /// Grey `bg-secondary` pill.
    static var intentSecondary: IntentSecondaryButtonStyle { .init() }
}

/// Round icon action (`h-[50px] w-[50px] rounded-full bg-secondary`, 20pt icon).
/// The label is required: it's the VoiceOver name of an icon-only button.
public struct IntentIconButton: View {
    private let systemImage: String
    private let label: String
    private let action: () -> Void

    public init(_ label: String, systemImage: String, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .light))
                .frame(width: IntentMetrics.iconButton, height: IntentMetrics.iconButton)
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel(label)
    }

    private struct IconButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(Color.intent.foreground)
                .background(Circle().fill(configuration.isPressed ? Color.intent.accent : Color.intent.secondary))
                .contentShape(Circle())
        }
    }
}

// MARK: - Selection

/// A full-width stacked choice card (`optionCardClass`): grey at rest, white with
/// black text once picked. Used one-question-per-screen in onboarding and the check-in.
public struct IntentOptionCard: View {
    private let title: String
    private let subtitle: String?
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, subtitle: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .intentText(.optionTitle)
                if let subtitle {
                    Text(subtitle)
                        .intentText(.optionSubtitle)
                        .foregroundStyle(isSelected ? Color.black.opacity(0.6) : Color.intent.mutedForeground)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, IntentSpacing.rowInset)
            .padding(.vertical, IntentSpacing.optionVertical)
            .foregroundStyle(isSelected ? Color.black : Color.intent.foreground)
        }
        .buttonStyle(SurfaceButtonStyle(
            fill: isSelected ? .white : Color.intent.card,
            pressedFill: isSelected ? .white : Color.intent.secondary,
            shape: RoundedRectangle(cornerRadius: IntentRadius.card, style: .continuous)
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A pill for tabs, segmented choices and multi-select chips (`chipClass`): white
/// with black medium text when selected, `bg-card` with muted text otherwise.
/// Put several in a horizontal `ScrollView`; never squeeze them into equal columns.
public struct IntentPill: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.intent(14, isSelected ? .medium : .regular))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? Color.black : Color.intent.mutedForeground)
        }
        .buttonStyle(SurfaceButtonStyle(
            fill: isSelected ? .white : Color.intent.card,
            pressedFill: isSelected ? .white : Color.intent.secondary,
            shape: Capsule()
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small caps badge (`ProgramBadge`): neutral `bg-secondary`, or the AI cyan tint.
public struct IntentBadge: View {
    public enum Tint: Sendable { case neutral, accent }

    private let text: String
    private let tint: Tint

    public init(_ text: String, tint: Tint = .neutral) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .intentText(.badge)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(tint == .accent ? Color.intent.sessionsCyan : Color.intent.foreground)
            .background(Capsule().fill(tint == .accent ? Color.intent.sessionsCyan.opacity(0.1) : Color.intent.secondary))
    }
}

private struct SurfaceButtonStyle<S: Shape>: ButtonStyle {
    let fill: Color
    let pressedFill: Color
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(shape.fill(configuration.isPressed ? pressedFill : fill))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Inset grouped list

/// An iOS inset grouped list (`RosterRow` / Settings): one `rounded-[26px] bg-card`
/// card holding `IntentGroupedRow`s. Hairlines start at the text inset and the
/// first row has none (each row draws its top hairline; the section clips the first).
public struct IntentGroupedSection<Content: View>: View {
    private let title: String?
    private let footer: String?
    private let content: Content

    public init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                IntentSectionTitle(title)
            }
            VStack(spacing: 0) { content }
                .padding(.top, -IntentMetrics.hairline)
                .frame(maxWidth: .infinity)
                .background(Color.intent.card)
                .clipShape(RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous))
            if let footer {
                Text(footer)
                    .intentText(.caption)
                    .foregroundStyle(Color.intent.mutedForeground)
                    .padding(.horizontal, IntentSpacing.rowInset)
                    .padding(.top, 8)
            }
        }
    }
}

/// One row of an `IntentGroupedSection`: title (+ muted subtitle) on the left, a
/// quiet trailing value or view on the right. No leading numbers, no colour bars.
public struct IntentGroupedRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let isDestructive: Bool
    private let showsChevron: Bool
    private let action: (() -> Void)?
    private let trailing: Trailing

    public init(
        _ title: String,
        subtitle: String? = nil,
        isDestructive: Bool = false,
        showsChevron: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isDestructive = isDestructive
        self.showsChevron = showsChevron
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(RowButtonStyle())
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .intentText(.rowTitle)
                    .foregroundStyle(isDestructive ? Color.intent.destructive : Color.intent.foreground)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .intentText(.caption)
                        .foregroundStyle(Color.intent.mutedForeground)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .intentText(.rowValue)
                .foregroundStyle(Color.intent.mutedForeground)
                .lineLimit(1)
                .fixedSize()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.intent.mutedForeground.opacity(0.7))
            }
        }
        .padding(.vertical, IntentSpacing.rowVertical)
        .padding(.trailing, IntentSpacing.rowInset)
        .overlay(alignment: .top) { IntentDivider() }
        .padding(.leading, IntentSpacing.rowInset)
        .contentShape(Rectangle())
    }

    private struct RowButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(configuration.isPressed ? Color.intent.secondary : Color.clear)
        }
    }
}

public extension IntentGroupedRow where Trailing == Text {
    init(_ title: String, subtitle: String? = nil, value: String, isDestructive: Bool = false, showsChevron: Bool = false, action: (() -> Void)? = nil) {
        self.init(title, subtitle: subtitle, isDestructive: isDestructive, showsChevron: showsChevron, action: action) { Text(value) }
    }
}

public extension IntentGroupedRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, isDestructive: Bool = false, showsChevron: Bool = false, action: (() -> Void)? = nil) {
        self.init(title, subtitle: subtitle, isDestructive: isDestructive, showsChevron: showsChevron, action: action) { EmptyView() }
    }
}
#endif

import IntentDesign
import SwiftUI

// Settings' own rows for an IntentGroupedSection, where IntentGroupedRow doesn't fit:
// boxless field rows, action rows whose subtitle wraps, and the in-group confirm sheet.
// Each row draws its top hairline at the text inset; the section clips the first one.

extension View {
    /// The grouped-row chrome: 20pt insets and a top hairline that starts at the text.
    func settingsRowChrome(trailing: CGFloat = IntentSpacing.rowInset) -> some View {
        padding(.trailing, trailing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { IntentDivider() }
            .padding(.leading, IntentSpacing.rowInset)
            .contentShape(Rectangle())
    }
}

/// Section title with an optional muted caption under it (`-mt-1.5 mb-3`).
struct SettingsSectionHeader: View {
    let title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IntentSectionTitle(title)
            if let caption {
                Text(caption)
                    .font(.intent(12.5))
                    .lineSpacing(4)
                    .foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -6)
                    .padding(.bottom, 12)
            }
        }
    }
}

/// "Name / Age / Weight": a fixed 80pt label, then the field (and any trailing control).
struct SettingsFieldRow<Field: View>: View {
    let label: String
    var error: String?
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.intent(15))
                    .frame(width: 80, alignment: .leading)
                field
            }
            .frame(minHeight: 52)
            .padding(.vertical, 2)
            if let error {
                Text(error)
                    .font(.intent(12.5))
                    .foregroundStyle(Color.intent.destructive)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -4)
                    .padding(.bottom, 12)
            }
        }
        .settingsRowChrome()
    }
}

/// A tappable row: title (red when destructive), a wrapping subtitle, an optional
/// trailing value, then a chevron, an icon or a spinner.
struct SettingsActionRow: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    var systemImage: String = "chevron.right"
    var isDestructive = false
    var isPending = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.intent(15))
                        .foregroundStyle(isDestructive ? Color.intent.destructive : Color.intent.foreground)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.intent(12.5))
                            .foregroundStyle(Color.intent.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing)
                        .font(.intent(15))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .fixedSize()
                }
                Group {
                    if isPending {
                        ProgressView().controlSize(.small).tint(Color.intent.mutedForeground)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 13, weight: .regular))
                    }
                }
                .foregroundStyle(Color.intent.mutedForeground)
                .frame(width: 16)
            }
            .frame(minHeight: 52)
            .padding(.vertical, 6)
            .settingsRowChrome(trailing: 16)
        }
        .buttonStyle(SettingsRowButtonStyle())
        .disabled(isPending)
    }
}

struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.intent.accent : Color.clear)
            .opacity(isEnabled ? 1 : 0.6)
    }
}

/// A confirm step that opens inside the group as a `bg-secondary` bottom-sheet row.
struct SettingsConfirmSheet<Confirm: View>: View {
    let title: String
    let message: String
    let onCancel: () -> Void
    @ViewBuilder let confirm: Confirm

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.intent(15, .medium))
            Text(message)
                .font(.intent(12.5))
                .lineSpacing(4)
                .foregroundStyle(Color.intent.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(SettingsSheetButtonStyle(kind: .outline))
                confirm
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .intentSurface(Color.intent.secondary, radius: IntentRadius.card)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

/// The confirm sheet's `h-10 flex-1 rounded-full` buttons, 13pt semibold.
struct SettingsSheetButtonStyle: ButtonStyle {
    enum Kind { case outline, primary, destructive }
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.intent(13, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .foregroundStyle(foreground)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.9 : 1)))
            .overlay {
                if kind == .outline {
                    Capsule().strokeBorder(Color.intent.foreground.opacity(0.9), lineWidth: IntentMetrics.hairline)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.6)
    }

    private var foreground: Color {
        switch kind {
        case .outline: Color.intent.foreground
        case .primary: Color.intent.primaryForeground
        case .destructive: Color.intent.destructiveForeground
        }
    }

    private var fill: Color {
        switch kind {
        case .outline: Color.clear
        case .primary: Color.intent.primary
        case .destructive: Color.intent.destructive
        }
    }
}

/// kg / lbs: a `bg-secondary` capsule with the picked unit white on black text.
struct SettingsUnitToggle: View {
    @Binding var unit: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(["kg", "lbs"], id: \.self) { u in
                Button { unit = u } label: {
                    Text(u)
                        .font(.intent(13, unit == u ? .medium : .regular))
                        .foregroundStyle(unit == u ? Color.black : Color.intent.mutedForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(unit == u ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(unit == u ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.intent.secondary))
        .fixedSize()
        .accessibilityLabel("Weight unit")
    }
}

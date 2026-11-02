import IntentAPI
import IntentCore
import IntentDesign
import SwiftUI
import UIKit

/// Debug states CI screenshots (see DebugScreen).
enum SettingsDebug {
    case none
    /// Scrolled to the calendar colours.
    case colors
    /// Scrolled to the bottom (subscription + account).
    case bottom
    /// The delete-account confirm open, scrolled to it.
    case deleteConfirm
    /// The mode-switch confirm open.
    case modeConfirm
}

/// The "You" tab (port of pages/settings.tsx): Profile, Training mode, Calendar
/// colours, Subscription and Account as iOS inset grouped lists, with boxless
/// right-aligned inputs and confirms that open inside the group. Guided tours skipped.
struct SettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    @Environment(WorkoutLauncher.self) private var launcher: WorkoutLauncher?
    @State private var data = SettingsData()

    @State private var name = ""
    @State private var weight = ""
    @State private var weightUnit = "kg"
    @State private var age = ""
    @State private var filled = false
    @State private var saved = false
    @State private var isSaving = false

    @State private var showModeConfirm = false
    @State private var pendingMode: String?
    @State private var isSwitchingMode = false

    @State private var colorMap: [String: String] = [:]
    @State private var colorWrites: [String: Task<Void, Never>] = [:]

    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var isOpeningPortal = false
    @State private var alert: SettingsAlert?

    private let debug: SettingsDebug

    init(debug: SettingsDebug = .none) {
        self.debug = debug
    }

    var body: some View {
        ScrollViewReader { proxy in
            IntentPage {
                header
                profileSection
                trainingSection.id("training")
                colorsSection.id("colors")
                subscriptionSection.id("subscription")
                accountSection.id("account")
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                await data.load(services.api)
                fillFields()
                await applyDebug(proxy)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // No nav bar: keep a black band under the status bar so scrolled content doesn't run behind the clock.
        .overlay(alignment: .top) {
            Color.intent.background.ignoresSafeArea(edges: .top).frame(height: 0)
        }
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }), presenting: alert) { _ in
            Button("OK", role: .cancel) {}
        } message: { a in
            Text(a.message)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "You", matching the tab it lives under.
            Text("You").intentText(.screenTitle)
            if let email = services.auth.state.user?.email {
                Text(email)
                    .font(.intent(15))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        let errors = SettingsLogic.profileErrors(age: age, weight: weight)
        return VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "Profile")
            IntentGroupedSection {
                SettingsFieldRow(label: "Name") {
                    TextField("", text: $name, prompt: placeholder("Your name"))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .modifier(SettingsInputStyle())
                        .onChange(of: name) { _, new in
                            if new.count > FieldLimits.maxProfileName { name = String(new.prefix(FieldLimits.maxProfileName)) }
                        }
                        .accessibilityLabel("Display name")
                }
                SettingsFieldRow(label: "Age", error: errors.age) {
                    TextField("", text: $age, prompt: placeholder("-"))
                        .keyboardType(.numberPad)
                        .modifier(SettingsInputStyle())
                        .accessibilityLabel("Age")
                }
                SettingsFieldRow(label: "Weight", error: errors.weight) {
                    TextField("", text: $weight, prompt: placeholder("-"))
                        .keyboardType(.decimalPad)
                        .modifier(SettingsInputStyle())
                        .accessibilityLabel("Weight")
                    // The input gives up the space, not the toggle.
                    SettingsUnitToggle(unit: $weightUnit)
                }
            }

            Button {
                Task { await saveProfile() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving { ProgressView().controlSize(.small).tint(Color.intent.primaryForeground) }
                    Text(saved ? "Saved" : "Save changes")
                }
            }
            .buttonStyle(SettingsSaveButtonStyle())
            .disabled(isSaving || errors.age != nil || errors.weight != nil)
            .padding(.top, 12)
        }
    }

    private func placeholder(_ text: String) -> Text {
        Text(text).foregroundStyle(Color.intent.mutedForeground.opacity(0.5))
    }

    private func fillFields() {
        guard !filled, let p = data.profile else { return }
        filled = true
        name = p.name ?? ""
        weight = p.weight.map { SettingsFormat.js($0) } ?? ""
        weightUnit = p.weightUnit ?? "kg"
        age = p.age.map(String.init) ?? ""
    }

    private func saveProfile() async {
        let errors = SettingsLogic.profileErrors(age: age, weight: weight)
        guard errors.age == nil, errors.weight == nil else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await data.saveProfile(SettingsLogic.profilePatch(name: name, age: age, weight: weight, weightUnit: weightUnit),
                                       client: services.api)
        } catch {
            // A profile saved before the ranges existed can still hold an impossible
            // value, which the server now rejects on the way back in.
            alert = SettingsAlert(title: "Couldn't save your profile",
                                  message: "Check that your age and weight look right, then try again.")
            return
        }
        saved = true
        try? await Task.sleep(for: .seconds(2))
        saved = false
    }

    // MARK: Training

    private var trainingSection: some View {
        let isAI = data.mode == "ai"
        return IntentGroupedSection("Training") {
            IntentGroupedRow("Mode") {
                if isAI {
                    IntentBadge("AI Coach", tint: .accent)
                } else {
                    IntentBadge("Independent")
                }
            }
            SettingsActionRow(
                title: isAI ? "Switch to Independent" : "Switch to AI Coach",
                subtitle: isAI ? "Build and manage your own program without AI." : "Get AI-generated programs and weekly adjustments."
            ) {
                pendingMode = isAI ? "independent" : "ai"
                showModeConfirm = true
            }
            if showModeConfirm {
                SettingsConfirmSheet(
                    title: "Switch to \(pendingMode == "ai" ? "AI Coach" : "Independent") mode?",
                    message: pendingMode == "ai"
                        ? "Your own program stays intact. We'll take you to AI Coach to set up and generate your program - it may ask a few quick questions first."
                        : "Your existing program will remain, but AI check-ins and adjustments will be disabled.",
                    onCancel: { showModeConfirm = false; pendingMode = nil }
                ) {
                    Button("Confirm") { Task { await switchMode() } }
                        .buttonStyle(SettingsSheetButtonStyle(kind: .primary))
                        .disabled(isSwitchingMode)
                }
            }
        }
    }

    private func switchMode() async {
        guard let target = pendingMode else { return }
        isSwitchingMode = true
        defer { isSwitchingMode = false }
        do {
            try await data.switchMode(to: target, client: services.api)
        } catch {
            // Web: an unhandled rejection - the sheet just stays open. Kept.
            appLog.error("settings: mode switch failed: \(String(describing: error), privacy: .public)")
            return
        }
        showModeConfirm = false
        pendingMode = nil
        // The web then routes to /program/ai or /program/my: the Program tab picks
        // the page from the new mode. Standalone debug hosts have no launcher.
        launcher?.selectTab?(.program)
    }

    // MARK: Calendar colours

    @ViewBuilder private var colorsSection: some View {
        let colors = data.colorLabels
        if !colors.labels.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSectionHeader(title: "Calendar colours",
                                      caption: "Each training day's colour, used on your calendar, your program page and in the editor.")
                IntentGroupedSection {
                    ForEach(colors.labels, id: \.self) { label in
                        let hex = DayColors.dayColorHex(label, order: colors.order, custom: mergedColors)
                        IntentGroupedRow(label) {
                            SettingsColorWell(hex: hex, label: label) { picked in
                                changeColor(label, picked)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Stored colours with this session's picks on top (the web's `colorMap`).
    private var mergedColors: [String: String] {
        var map: [String: String] = [:]
        for c in data.storedColors { map[c.dayLabel] = c.hexColor }
        return map.merging(colorMap) { _, picked in picked }
    }

    /// The web upserts on every `input` event of the colour input; the native picker
    /// streams changes while dragging, so the write waits for 400ms of quiet.
    private func changeColor(_ label: String, _ hex: String) {
        guard mergedColors[label] != hex else { return }
        colorMap[label] = hex
        colorWrites[label]?.cancel()
        let client = services.api
        colorWrites[label] = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do { try await data.upsertColor(label: label, hex: hex, client: client) } catch {
                appLog.error("settings: colour save failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: Subscription

    private var subscriptionSection: some View {
        IntentGroupedSection("Subscription") {
            if data.subscriptionLoading {
                IntentGroupedRow("Loading...")
            } else {
                IntentGroupedRow("Plan") {
                    HStack(spacing: 12) {
                        if let end = data.subscription?.currentPeriodEnd, let date = SettingsLogic.renewsDate(end) {
                            Text("Renews \(date)").font(.intent(13))
                        }
                        IntentBadge(data.isPro ? "Pro" : "Free")
                    }
                }
                if !data.isPro {
                    // PAYMENTS PLACEHOLDER: the web opens a Stripe checkout here
                    // (createCheckoutSession). StoreKit vs Stripe isn't decided, so the
                    // native app has no purchase flow yet - this row does nothing.
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to Pro").font(.intent(15))
                            Text("Unlimited programs, weekly AI adjustments and full progress tracking.")
                                .font(.intent(12.5))
                                .foregroundStyle(Color.intent.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        IntentBadge("Coming soon").fixedSize()
                    }
                    .frame(minHeight: 52)
                    .padding(.vertical, 6)
                    .settingsRowChrome()
                } else {
                    SettingsActionRow(title: "Manage billing", systemImage: "arrow.up.right.square", isPending: isOpeningPortal) {
                        Task { await openPortal() }
                    }
                }
            }
        }
    }

    private func openPortal() async {
        isOpeningPortal = true
        defer { isOpeningPortal = false }
        do {
            if let url = try await data.portalURL(client: services.api) { openURL(url) }
        } catch {
            appLog.error("settings: portal failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Account

    /// Destructive actions are red text, not a red box.
    private var accountSection: some View {
        IntentGroupedSection("Account") {
            SettingsActionRow(title: "Sign out") {
                Task { try? await services.auth.signOut() }
            }
            SettingsActionRow(title: "Delete account", subtitle: "Permanently delete your account and all data.", isDestructive: true) {
                showDeleteConfirm = true
            }
            if showDeleteConfirm {
                SettingsConfirmSheet(
                    title: "Delete everything?",
                    message: "This will permanently delete your account and all training data. This cannot be undone.",
                    onCancel: { showDeleteConfirm = false }
                ) {
                    Button { Task { await deleteAccount() } } label: {
                        HStack(spacing: 8) {
                            if isDeleting { ProgressView().controlSize(.small).tint(Color.intent.destructiveForeground) }
                            Text("Yes, delete everything")
                        }
                    }
                    .buttonStyle(SettingsSheetButtonStyle(kind: .destructive))
                    .disabled(isDeleting)
                }
            }
        }
    }

    /// Application data first, then the sign-in account. If the server call fails we
    /// stop: the account can still sign in and retry.
    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await data.deleteAccount(client: services.api)
        } catch {
            alert = SettingsAlert(title: "Couldn't delete your data", message: "Nothing was deleted. Please try again.")
            return
        }
        // Then the Clerk user itself, as the web's `user.delete()` (Apple requires real
        // in-app account deletion). Signing out covers the case where that fails.
        showDeleteConfirm = false
        do {
            try await services.auth.deleteUser()
        } catch {
            appLog.error("settings: Clerk user delete failed: \(String(describing: error), privacy: .public)")
        }
        try? await services.auth.signOut()
    }

    // MARK: Debug

    private func applyDebug(_ proxy: ScrollViewProxy) async {
        switch debug {
        case .none: return
        case .colors:
            try? await Task.sleep(for: .milliseconds(150))
            proxy.scrollTo("colors", anchor: .top)
        case .bottom:
            try? await Task.sleep(for: .milliseconds(150))
            proxy.scrollTo("account", anchor: .bottom)
        case .deleteConfirm:
            showDeleteConfirm = true
            try? await Task.sleep(for: .milliseconds(250))
            proxy.scrollTo("account", anchor: .bottom)
        case .modeConfirm:
            pendingMode = data.mode == "ai" ? "independent" : "ai"
            showModeConfirm = true
            try? await Task.sleep(for: .milliseconds(250))
            proxy.scrollTo("training", anchor: .center)
        }
    }
}

struct SettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Weight as JS `toString()` prints it: 78.4, 80 (no ".0").
enum SettingsFormat {
    static func js(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

/// Boxless, right-aligned value input: the row is the field, like iOS Settings.
private struct SettingsInputStyle: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .font(.intent(15))
            .multilineTextAlignment(.trailing)
            .foregroundStyle(focused ? Color.intent.foreground : Color.intent.mutedForeground)
            .tint(Color.intent.foreground)
            .frame(maxWidth: .infinity)
    }
}

/// "Save changes": `h-11 rounded-full bg-primary px-6`, 13pt semibold caps.
private struct SettingsSaveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.intent(13, .semibold))
            .tracking(0.78)
            .textCase(.uppercase)
            .foregroundStyle(Color.intent.primaryForeground)
            .padding(.horizontal, 24)
            .frame(height: 44)
            .background(Capsule().fill(Color.intent.primary.opacity(configuration.isPressed ? 0.9 : 1)))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.6)
    }
}

/// The day's colour disc; tapping it opens the system colour picker (the web's hidden
/// `<input type="color">` over the disc).
private struct SettingsColorWell: View {
    let hex: String
    let label: String
    let onPick: (String) -> Void

    var body: some View {
        let rgb = DayColors.hexToRgb(hex)
        let color = Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
        ZStack {
            Circle().fill(color).frame(width: 28, height: 28)
            ColorPicker("Colour for \(label)", selection: Binding(
                get: { color },
                set: { new in
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    UIColor(new).getRed(&r, green: &g, blue: &b, alpha: &a)
                    onPick(SettingsLogic.hex(r: Double(r), g: Double(g), b: Double(b)))
                }
            ), supportsOpacity: false)
            .labelsHidden()
            // Invisible but still hit-testable, so the disc is the button.
            .opacity(0.02)
            .frame(width: 28, height: 28)
        }
    }
}

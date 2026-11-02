import IntentCore
import IntentDesign
import SwiftUI

// The logger's sheets and empty states: components/workout/ConfirmSheet.tsx,
// components/calibration/CalibrationFinishSheet.tsx and log.tsx's LogEmptyState.
// Native bottom sheets in Sessions chrome (bg-card, 30pt top radius, grabber).

extension View {
    func logSheetChrome(height: CGFloat) -> some View {
        presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(IntentRadius.hero)
            .presentationBackground(Color.intent.card)
            .preferredColorScheme(.dark)
    }
}

/// Two-button confirmation. Tapping outside (or dragging down) is the cancel button.
struct LogConfirmSheet: View {
    let title: String
    let message: String
    let cancelLabel: String
    let confirmLabel: String
    let destructive: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.intent(24, .light)).tracking(-0.24).foregroundStyle(Color.intent.foreground)
                Text(message).intentText(.lede).foregroundStyle(Color.intent.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text(cancelLabel).font(.intent(14, .medium))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(Color.intent.foreground)
                        .background(Capsule().fill(Color.intent.secondary))
                }
                .buttonStyle(.plain)
                Button(action: onConfirm) {
                    Text(confirmLabel).font(.intent(14, .semibold))
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(destructive ? Color.intent.destructiveForeground : Color.intent.primaryForeground)
                        .background(Capsule().fill(destructive ? Color.intent.destructive : Color.intent.primary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// "Good job" + a free-form note when a calibration session is finished. The note
/// goes to workout_logs.notes: with the exercise notes it's what the coach reads at
/// the calibration review.
struct CalibrationFinishSheet: View {
    let saving: Bool
    let onFinish: (String?) -> Void
    @State private var note = ""

    var body: some View {
        VStack(spacing: 0) {
            IntentSunMark(size: 40)
                .padding(.top, 28)
                .accessibilityHidden(true)
            Text("Good job").font(.intent(24, .light)).tracking(-0.24).padding(.top, 16)
            Text("Anything on your mind about this session?")
                .intentText(.lede).foregroundStyle(Color.intent.mutedForeground)
                .multilineTextAlignment(.center).padding(.top, 6)
            LogNotesField(text: note,
                          placeholder: "Write anything: the gym was busy, the session ran long, a machine was missing...",
                          lines: 4...6) { note = String($0.prefix(2000)) }
                .padding(.top, 16)
            Text("Your coach reads this at your calibration review.")
                .font(.intent(11.5)).foregroundStyle(Color.intent.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            Button {
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                onFinish(trimmed.isEmpty ? nil : trimmed)
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.black) }
                    Text("Save and finish").font(.intent(14, .semibold))
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(Color.intent.primaryForeground)
                .background(Capsule().fill(Color.intent.primary.opacity(saving ? 0.6 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(saving)
            .padding(.top, 16)
            Button { onFinish(nil) } label: {
                Text("Finish without a note").font(.intent(13)).foregroundStyle(Color.intent.mutedForeground)
                    .frame(maxWidth: .infinity).frame(height: 40)
            }
            .buttonStyle(.plain)
            .disabled(saving)
            .padding(.top, 8)
        }
        .foregroundStyle(Color.intent.foreground)
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .interactiveDismissDisabled(saving)
    }
}

/// The page when there's nothing to log: no program yet, or no session open.
struct LogEmptyState: View {
    let title: String
    let message: String
    let cta: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "dumbbell")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.intent.mutedForeground)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.intent.card))
                .padding(.bottom, 20)
            Text(title).font(.intent(28, .light)).tracking(-0.56).foregroundStyle(Color.intent.foreground)
                .multilineTextAlignment(.center)
            Text(message).intentText(.lede).foregroundStyle(Color.intent.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 10)
                .padding(.bottom, 28)
            Button(action: action) {
                Text(cta).intentText(.button)
                    .padding(.horizontal, 32)
                    .frame(height: IntentMetrics.controlHeight)
                    .foregroundStyle(Color.intent.primaryForeground)
                    .background(Capsule().fill(Color.intent.primary))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

/// Stand-in for the web's /exercises/how-to page (not ported yet): the exercise
/// name and the program's cue.
struct LogHowToSheet: View {
    let name: String
    let muscle: String
    let cue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(muscle).intentText(.caps).foregroundStyle(Color.intent.mutedForeground)
            Text(name).font(.intent(24, .light)).foregroundStyle(Color.intent.foreground)
            Text(cue ?? "A step-by-step guide for this exercise is coming soon.")
                .intentText(.body).foregroundStyle(Color.intent.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LogHowToItem: Identifiable {
    let name: String
    let muscle: String
    let cue: String?
    var id: String { name }
}

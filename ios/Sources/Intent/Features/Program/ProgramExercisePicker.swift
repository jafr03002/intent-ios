import IntentCore
import IntentDesign
import SwiftUI

/// The builder's exercise name field (web components/program/ExerciseNamePicker.tsx):
/// free text that also suggests from the exercise library. The text is the source of
/// truth - anything typed saves as-is; choosing a suggestion also reports its primary
/// muscle. Suggestions show while typing (2+ characters); the dumbbell button browses
/// the library by muscle group in a sheet.
///
/// Not ported: the web popover's per-exercise detail side and arrow-key navigation.
struct ProgramExerciseNameField: View {
    @Binding var name: String
    let invalid: Bool
    var focus: FocusState<UUID?>.Binding
    let rowId: UUID
    let onPick: (LibraryExercise) -> Void
    var startsBrowsing = false

    @State private var browsing = false
    /// Hides the suggestions after a pick until the text changes again.
    @State private var dismissedFor: String?

    private static let minQuery = 2

    private var suggestions: [LibraryExercise] {
        guard focus.wrappedValue == rowId, dismissedFor != name,
              JS_trimCount(name) >= Self.minQuery else { return [] }
        return Array(ExerciseLibrary.search(name).prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                TextField("", text: $name, prompt: Text("Exercise name").foregroundStyle(Color.intent.mutedForeground))
                    .font(.intent(14, .regular))
                    .foregroundStyle(Color.intent.foreground)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused(focus, equals: rowId)
                    .onChange(of: name) { _, new in
                        if new.count > FieldLimits.maxExerciseName { name = String(new.prefix(FieldLimits.maxExerciseName)) }
                    }
                Button { browsing = true } label: {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Color.intent.mutedForeground)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Browse the exercise library")
            }
            .padding(.trailing, -6)
            .programFieldBox(invalid: invalid)

            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { i, ex in
                        Button {
                            dismissedFor = ex.name
                            onPick(ex)
                        } label: {
                            ProgramLibraryRow(exercise: ex)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { if i > 0 { IntentDivider() } }
                    }
                }
                .background(Color.intent.accent, in: RoundedRectangle(cornerRadius: IntentRadius.lg, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: IntentRadius.lg, style: .continuous))
            }
        }
        .sheet(isPresented: $browsing) {
            ProgramLibrarySheet { ex in
                browsing = false
                dismissedFor = ex.name
                onPick(ex)
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Color.intent.card)
        }
        .task {
            guard startsBrowsing else { return }
            try? await Task.sleep(for: .milliseconds(600))
            browsing = true
        }
    }

    private func JS_trimCount(_ s: String) -> Int {
        s.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
}

/// A library suggestion: the name, and its primary muscle with the muscle's dot.
struct ProgramLibraryRow: View {
    let exercise: LibraryExercise

    var body: some View {
        HStack(spacing: 10) {
            Text(exercise.name)
                .font(.intent(14, .regular))
                .foregroundStyle(Color.intent.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                Circle().fill(Color.programHSL(exercise.muscle.color)).frame(width: 6, height: 6)
                Text(exercise.muscle.label)
            }
            .font(.intent(12, .regular))
            .foregroundStyle(Color.intent.mutedForeground)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// Browse the library: collapsed muscle groups, one open at a time.
struct ProgramLibrarySheet: View {
    let onPick: (LibraryExercise) -> Void
    var initiallyOpen: Muscle?

    @State private var openGroup: Muscle?
    @State private var didInit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color.intent.accent).frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity).padding(.bottom, 18)
                Text("Exercise library")
                    .font(.intent(22, .regular))
                    .foregroundStyle(Color.intent.foreground)
                Text("Pick one to fill in its name and muscle. You can still type any name.")
                    .font(.intent(13.5, .regular))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .padding(.top, 6)
                    .padding(.bottom, 18)
                VStack(spacing: 0) {
                    ForEach(Array(ExerciseLibrary.groups.enumerated()), id: \.offset) { i, group in
                        groupRow(group, first: i == 0)
                    }
                }
                .background(Color.intent.secondary)
                .clipShape(RoundedRectangle(cornerRadius: IntentRadius.groupedList, style: .continuous))
            }
            .padding(.horizontal, IntentSpacing.gutter)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if !didInit { didInit = true; openGroup = initiallyOpen }
        }
    }

    @ViewBuilder private func groupRow(_ group: LibraryGroup, first: Bool) -> some View {
        let isOpen = openGroup == group.muscle
        Button {
            withAnimation(.easeOut(duration: 0.2)) { openGroup = isOpen ? nil : group.muscle }
        } label: {
            HStack(spacing: 10) {
                Circle().fill(Color.programHSL(group.muscle.color)).frame(width: 7, height: 7)
                Text(group.muscle.label)
                    .intentText(.rowTitle)
                    .foregroundStyle(Color.intent.foreground)
                Spacer()
                Text("\(group.names.count)")
                    .intentText(.rowValue)
                    .foregroundStyle(Color.intent.mutedForeground)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.intent.mutedForeground)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.horizontal, IntentSpacing.rowInset)
            .padding(.vertical, IntentSpacing.rowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { if !first { IntentDivider().padding(.leading, IntentSpacing.rowInset) } }
        if isOpen {
            ForEach(group.names, id: \.self) { name in
                Button { onPick(LibraryExercise(name: name, muscle: group.muscle)) } label: {
                    Text(name)
                        .font(.intent(14, .regular))
                        .foregroundStyle(Color.intent.foreground.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, IntentSpacing.rowInset + 17)
                        .padding(.trailing, IntentSpacing.rowInset)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

import SwiftUI

// MARK: - Quiz (opción múltiple)

struct QuizExerciseView: View {
    let exercise: Exercise
    let onSubmit: (Answer) -> Void

    @State private var selected: Int?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array((exercise.options ?? []).enumerated()), id: \.offset) { index, option in
                QuizOptionRow(
                    index: index,
                    option: option,
                    isSelected: selected == index,
                    letter: letter(for: index)
                ) {
                    selected = index
                    onSubmit(.quiz(index: index))
                }
            }
        }
    }

    private func letter(for index: Int) -> String {
        String(UnicodeScalar(65 + index) ?? "A")
    }
}

private struct QuizOptionRow: View {
    let index: Int
    let option: String
    let isSelected: Bool
    let letter: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(letter)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                Text(option)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding()
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        isSelected
            ? Color.accentColor.opacity(0.15)
            : Color(.secondarySystemBackground)
    }
}

// MARK: - Autocompletar

struct FillBlankExerciseView: View {
    let exercise: Exercise
    let onSubmit: (Answer) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            TextField("Escribe la palabra que falta…", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)

            Button("Comprobar", action: submit)
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isFocused = false
        onSubmit(.fillBlank(text: trimmed))
    }
}

// MARK: - Ordenar pasos

struct ReorderExerciseView: View {
    let exercise: Exercise
    let onSubmit: (Answer) -> Void

    @State private var steps: [String] = []

    init(exercise: Exercise, onSubmit: @escaping (Answer) -> Void) {
        self.exercise = exercise
        self.onSubmit = onSubmit
        _steps = State(initialValue: exercise.steps ?? [])
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        Text(step)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            move(from: index, direction: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == 0)
                        Button {
                            move(from: index, direction: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == steps.count - 1)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }

            Button {
                onSubmit(.reorder(order: steps.indices.map { index in
                    steps.firstIndex(of: (exercise.steps ?? [])[index]) ?? index
                }))
            } label: {
                Label("Comprobar orden", systemImage: "checkmark")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func move(from index: Int, direction: Int) {
        let target = index + direction
        guard steps.indices.contains(target) else { return }
        withAnimation(.snappy) {
            steps.swapAt(index, target)
        }
    }
}

// MARK: - Emparejar conceptos

struct MatchingExerciseView: View {
    let exercise: Exercise
    let onSubmit: (Answer) -> Void

    @State private var selectedLeft: Int?
    @State private var pairs: [Int?]

    init(exercise: Exercise, onSubmit: @escaping (Answer) -> Void) {
        self.exercise = exercise
        self.onSubmit = onSubmit
        _pairs = State(initialValue: Array(repeating: nil,
                                           count: exercise.left?.count ?? 0))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                leftColumn
                rightColumn
            }

            if !pairedRightItems.isEmpty {
                Text("Emparejados: \(pairedRightItems.count) de \(exercise.left?.count ?? 0)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                onSubmit(.matching(pairs: pairs.map { $0 ?? -1 }))
            } label: {
                Label("Comprobar", systemImage: "checkmark")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pairs.contains(nil))
        }
    }

    private var pairedRightItems: [Int] {
        pairs.compactMap { $0 }
    }

    private var leftColumn: some View {
        VStack(spacing: 10) {
            ForEach(Array((exercise.left ?? []).enumerated()), id: \.offset) { index, item in
                MatchingItemButton(
                    text: item,
                    isHighlighted: selectedLeft == index,
                    isPaired: pairs[index] != nil,
                    fill: selectedLeft == index
                        ? Color.accentColor.opacity(0.2)
                        : Color(.secondarySystemBackground)
                ) {
                    selectLeft(index)
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 10) {
            ForEach(Array((exercise.right ?? []).enumerated()), id: \.offset) { index, item in
                MatchingItemButton(
                    text: item,
                    isHighlighted: false,
                    isPaired: pairedRightItems.contains(index),
                    fill: pairedRightItems.contains(index)
                        ? Color.green.opacity(0.15)
                        : Color(.secondarySystemBackground)
                ) {
                    selectRight(index)
                }
            }
        }
    }

    private func selectLeft(_ index: Int) {
        if selectedLeft == index {
            selectedLeft = nil
        } else {
            selectedLeft = index
        }
    }

    private func selectRight(_ index: Int) {
        guard let selectedLeft else { return }
        pairs[selectedLeft] = index
        self.selectedLeft = nil
    }
}

private struct MatchingItemButton: View {
    let text: String
    let isHighlighted: Bool
    let isPaired: Bool
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(fill)
                )
        }
        .buttonStyle(.plain)
        .disabled(isPaired)
        .opacity(isPaired ? 0.4 : 1)
    }
}
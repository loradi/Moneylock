import Foundation

enum ExerciseValidator {

    /// Normaliza texto para comparación tolerante:
    /// minúsculas, sin acentos, sin signos de puntuación, sin espacios dobles.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "es"))
        let noPunctuation = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        let words = String(String.UnicodeScalarView(noPunctuation))
            .split(whereSeparator: \.isWhitespace)
        return words.joined(separator: " ")
    }

    static func validate(_ exercise: Exercise, answer: Answer) -> ValidationResult {
        switch (exercise.type, answer) {
        case (.quiz, .quiz(let index)):
            let expectedIndex = exercise.correctIndex ?? -1
            return result(
                isCorrect: index == expectedIndex,
                exercise: exercise,
                expected: expectedText(exercise, expectedIndex))

        case (.fillBlank, .fillBlank(let text)):
            let normalizedInput = normalize(text)
            let accepted = (exercise.correct ?? []).map { normalize($0) }
            let isCorrect = !accepted.isEmpty && accepted.contains(normalizedInput)
            return result(
                isCorrect: isCorrect,
                exercise: exercise,
                expected: accepted.first ?? "")

        case (.reorder, .reorder(let order)):
            let expectedOrder = exercise.correctOrder ?? []
            return result(
                isCorrect: order == expectedOrder,
                exercise: exercise,
                expected: expectedStepsText(exercise, expectedOrder))

        case (.matching, .matching(let pairs)):
            let expectedPairs = exercise.correctPairs ?? []
            return result(
                isCorrect: pairs == expectedPairs,
                exercise: exercise,
                expected: expectedPairsText(exercise, expectedPairs))

        default:
            return result(isCorrect: false, exercise: exercise,
                          expected: "")
        }
    }

    private static func result(isCorrect: Bool, exercise: Exercise,
                               expected: String) -> ValidationResult {
        ValidationResult(isCorrect: isCorrect,
                         expected: expected,
                         explanation: exercise.explanation)
    }

    private static func expectedText(_ exercise: Exercise, _ index: Int) -> String {
        let options = exercise.options ?? []
        guard options.indices.contains(index) else { return "" }
        return options[index]
    }

    private static func expectedStepsText(_ exercise: Exercise, _ order: [Int]) -> String {
        let steps = exercise.steps ?? []
        return order.compactMap { steps.indices.contains($0) ? steps[$0] : nil }
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    private static func expectedPairsText(_ exercise: Exercise, _ pairs: [Int]) -> String {
        let left = exercise.left ?? []
        let right = exercise.right ?? []
        return pairs.enumerated().compactMap { (index, rightIndex) in
            guard left.indices.contains(index), right.indices.contains(rightIndex) else {
                return nil
            }
            return "\(left[index]) → \(right[rightIndex])"
        }.joined(separator: "\n")
    }
}
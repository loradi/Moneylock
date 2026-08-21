import XCTest
@testable import LearnPath

final class ExerciseValidatorTests: XCTestCase {

    // MARK: - Normalización

    func testNormalizeRemovesAccentsAndCase() {
        XCTAssertEqual(ExerciseValidator.normalize("EléCTRONES"),
                       "electrones")
    }

    func testNormalizeRemovesPunctuationAndDoubleSpaces() {
        XCTAssertEqual(ExerciseValidator.normalize("  protones,   neutrones. "),
                       "protones neutrones")
    }

    func testNormalizeNumbersAreKept() {
        XCTAssertEqual(ExerciseValidator.normalize("Fórmula H2O"),
                       "formula h2o")
    }

    // MARK: - Quiz

    func testQuizCorrectIndex() {
        let exercise = Exercise(
            type: .quiz,
            prompt: "¿Qué es un quark?",
            options: ["Partícula elemental", "Una estrella", "Un átomo", "Una fuerza"],
            correctIndex: 0,
            correct: nil, steps: nil, correctOrder: nil,
            left: nil, right: nil, correctPairs: nil,
            explanation: "Los quarks son partículas fundamentales.")
        let result = ExerciseValidator.validate(
            exercise, answer: .quiz(index: 0))
        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.expected, "Partícula elemental")
    }

    func testQuizWrongIndex() {
        let exercise = Exercise(
            type: .quiz,
            prompt: "p",
            options: ["A", "B", "C", "D"],
            correctIndex: 2,
            correct: nil, steps: nil, correctOrder: nil,
            left: nil, right: nil, correctPairs: nil,
            explanation: "e")
        let result = ExerciseValidator.validate(
            exercise, answer: .quiz(index: 0))
        XCTAssertFalse(result.isCorrect)
        XCTAssertEqual(result.expected, "C")
    }

    // MARK: - FillBlank

    func testFillBlankExact() {
        let exercise = Exercise(
            type: .fillBlank,
            prompt: "El átomo tiene ______",
            options: nil, correctIndex: nil,
            correct: ["electrones"],
            steps: nil, correctOrder: nil,
            left: nil, right: nil, correctPairs: nil,
            explanation: "e")
        let result = ExerciseValidator.validate(
            exercise, answer: .fillBlank(text: "electrones"))
        XCTAssertTrue(result.isCorrect)
    }

    func testFillBlankToleratesAccentsAndCase() {
        let exercise = Exercise(
            type: .fillBlank,
            prompt: "La capital de Francia es ______",
            options: nil, correctIndex: nil,
            correct: ["París"],
            steps: nil, correctOrder: nil,
            left: nil, right: nil, correctPairs: nil,
            explanation: "e")
        let result = ExerciseValidator.validate(
            exercise, answer: .fillBlank(text: "PARIS"))
        XCTAssertTrue(result.isCorrect)
    }

    func testFillBlankAcceptsAnyAcceptedVariant() {
        let exercise = Exercise(
            type: .fillBlank,
            prompt: "Resultado de 2+2: ______",
            options: nil, correctIndex: nil,
            correct: ["cuatro", "4"],
            steps: nil, correctOrder: nil,
            left: nil, right: nil, correctPairs: nil,
            explanation: "e")
        XCTAssertTrue(ExerciseValidator.validate(
            exercise, answer: .fillBlank(text: "4")).isCorrect)
        XCTAssertTrue(ExerciseValidator.validate(
            exercise, answer: .fillBlank(text: "cuatro")).isCorrect)
        XCTAssertFalse(ExerciseValidator.validate(
            exercise, answer: .fillBlank(text: "cinco")).isCorrect)
    }

    func testFillBlankWrongAnswer() {
        let exercise = Exercise(
            type: .fillBlank,
            prompt: "El átomo tiene ______",
            options: nil, correctIndex: nil,
            correct: ["electrones"],
            steps: nil, correctOrder: nil,
            left: nil, right: nil, correctPairs: nil,
            explanation: "e")
        let result = ExerciseValidator.validate(
            exercise, answer: .fillBlank(text: "protones"))
        XCTAssertFalse(result.isCorrect)
    }

    // MARK: - Reorder

    func testReorderCorrectOrder() {
        let exercise = Exercise(
            type: .reorder,
            prompt: "Ordena el método científico",
            options: nil, correctIndex: nil,
            correct: nil,
            steps: ["Observar", "Hipótesis", "Experimentar", "Concluir"],
            correctOrder: [0, 1, 2, 3],
            left: nil, right: nil, correctPairs: nil,
            explanation: "e")
        let result = ExerciseValidator.validate(
            exercise, answer: .reorder(order: [0, 1, 2, 3]))
        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.expected, "1. Observar\n2. Hipótesis\n3. Experimentar\n4. Concluir")
    }

    func testReorderWrongOrder() {
        let exercise = Exercise(
            type: .reorder,
            prompt: "Ordena",
            options: nil, correctIndex: nil,
            correct: nil,
            steps: ["A", "B", "C"],
            correctOrder: [0, 1, 2],
            left: nil, right: nil, correctPairs: nil,
            explanation: "e")
        let result = ExerciseValidator.validate(
            exercise, answer: .reorder(order: [2, 1, 0]))
        XCTAssertFalse(result.isCorrect)
    }

    // MARK: - Matching

    func testMatchingCorrectPairs() {
        let exercise = Exercise(
            type: .matching,
            prompt: "Empareja",
            options: nil, correctIndex: nil,
            correct: nil,
            steps: nil, correctOrder: nil,
            left: ["ADN", "ARN", "Proteína"],
            right: ["Ácido desoxirribonucleico", "Ácido ribonucleico", "Cadena de aminoácidos"],
            correctPairs: [0, 1, 2],
            explanation: "e")
        let result = ExerciseValidator.validate(
            exercise, answer: .matching(pairs: [0, 1, 2]))
        XCTAssertTrue(result.isCorrect)
    }

    func testMatchingWrongPairs() {
        let exercise = Exercise(
            type: .matching,
            prompt: "Empareja",
            options: nil, correctIndex: nil,
            correct: nil,
            steps: nil, correctOrder: nil,
            left: ["ADN", "ARN", "Proteína"],
            right: ["R1", "R2", "R3"],
            correctPairs: [0, 1, 2],
            explanation: "e")
        let result = ExerciseValidator.validate(
            exercise, answer: .matching(pairs: [1, 0, 2]))
        XCTAssertFalse(result.isCorrect)
    }

    // MARK: - Tipos no coincidentes

    func testAnswerTypeMismatchFails() {
        let exercise = Exercise(
            type: .quiz,
            prompt: "p",
            options: ["A", "B", "C", "D"],
            correctIndex: 0,
            correct: nil, steps: nil, correctOrder: nil,
            left: nil, right: nil, correctPairs: nil,
            explanation: "e")
        let result = ExerciseValidator.validate(
            exercise, answer: .fillBlank(text: "A"))
        XCTAssertFalse(result.isCorrect)
    }
}
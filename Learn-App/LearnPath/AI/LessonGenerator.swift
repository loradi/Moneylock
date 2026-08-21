import Foundation

/// Generates a lesson's exercises on-demand, with the correct answer
/// embedded in the JSON (see spec §4.1).
actor LessonGenerator {
    private let model: any ModelProvider
    private let maxAttempts = 3

    init(model: any ModelProvider) {
        self.model = model
    }

    func generateLesson(
        topic: String,
        levelTitle: String,
        difficulty: Int,
        lessonTitle: String,
        previousContext: String? = nil
    ) async throws -> LearningPath.Level.Lesson {
        let types = ExerciseType.allCases
        let typeList = types.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")

        let contextBlock = previousContext.map {
            """
            The exercises should build on what's already been learned, without repeating it:
            \($0)
            """
        } ?? ""

        let prompt = """
        You are an expert tutor who creates instructional exercises.
        Topic: "\(topic)" — Level: "\(levelTitle)" (difficulty \(difficulty) of 4) — Lesson: "\(lessonTitle)".
        \(contextBlock)

        Create 5 review exercises for this lesson, one of each type: \(typeList).

        Respond ONLY with a JSON array, no additional text. Each exercise with this structure:

        {
          "type": "quiz" | "fillBlank" | "reorder" | "matching",
          "prompt": "Exercise prompt",
          "options": ["A", "B", "C", "D"],
          "correctIndex": 0,
          "correct": ["correct answer"],
          "steps": ["step 1", "step 2", "step 3"],
          "correctOrder": [0, 1, 2],
          "left": ["left A", "left B", "left C"],
          "right": ["right A", "right B", "right C"],
          "correctPairs": [0, 1, 2],
          "explanation": "Brief explanation of why it's correct"
        }

        Rules:
        - Only use the fields relevant to each type; the rest can be omitted or null.
        - quiz: 4 options, correctIndex points to the correct option.
        - fillBlank: the prompt contains "______" where the missing word goes; correct has 1-3 acceptable variants.
        - reorder: 3-5 steps; correctOrder is the correct order of the indices.
        - matching: 3 pairs; correctPairs[i] = the index in right that pairs with left[i].
        - Correct answers must be unambiguously determined by the level's content.
        - explanation: 1-2 sentences in English teaching why.
        - All content in English.
        """

        var lastError: Error?
        for _ in 0..<maxAttempts {
            do {
                let raw = try await model.generate(
                    messages: [LLMMessage(role: .user, content: prompt)],
                    maxTokens: 1500)
                let exercises: [Exercise] = try JSONParser.decode([Exercise].self, from: raw)
                let valid = exercises.filter { isValid($0) }
                if valid.count >= 3 {
                    return LearningPath.Level.Lesson(
                        title: lessonTitle,
                        exercises: Array(valid.prefix(5)))
                }
                lastError = GenerationError.invalidJSON(
                    "only \(valid.count)/\(exercises.count) exercises valid")
            } catch {
                lastError = error
            }
        }
        throw lastError ?? GenerationError.invalidJSON("unknown")
    }

    private func isValid(_ exercise: Exercise) -> Bool {
        guard !exercise.prompt.isEmpty else { return false }
        switch exercise.type {
        case .quiz:
            guard let options = exercise.options, options.count == 4,
                  let index = exercise.correctIndex,
                  options.indices.contains(index) else { return false }
            return !options.contains(where: { $0.isEmpty })
        case .fillBlank:
            guard let correct = exercise.correct, !correct.isEmpty,
                  exercise.prompt.contains("______") else { return false }
            return !correct.contains(where: { $0.isEmpty })
        case .reorder:
            guard let steps = exercise.steps, steps.count >= 3,
                  let order = exercise.correctOrder, order.count == steps.count,
                  Set(order) == Set(0..<steps.count) else { return false }
            return !steps.contains(where: { $0.isEmpty })
        case .matching:
            guard let left = exercise.left, let right = exercise.right,
                  left.count == right.count, left.count >= 3,
                  let pairs = exercise.correctPairs, pairs.count == left.count,
                  Set(pairs) == Set(0..<right.count) else { return false }
            return !left.contains(where: { $0.isEmpty }) &&
                !right.contains(where: { $0.isEmpty })
        }
    }
}
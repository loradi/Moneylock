import Foundation

/// Genera los ejercicios de una lección on-demand, con la respuesta
/// correcta embebida en el JSON (ver spec §4.1).
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
            Los ejercicios deben continuar lo ya aprendido, sin repetir:
            \($0)
            """
        } ?? ""

        let prompt = """
        Eres un tutor experto que crea ejercicios didácticos.
        Tema: "\(topic)" — Nivel: "\(levelTitle)" (dificultad \(difficulty) de 4) — Lección: "\(lessonTitle)".
        \(contextBlock)

        Crea 5 ejercicios de repaso para esta lección, uno de cada tipo: \(typeList).

        Responde ÚNICAMENTE con un array JSON, sin texto adicional. Cada ejercicio con esta estructura:

        {
          "type": "quiz" | "fillBlank" | "reorder" | "matching",
          "prompt": "Enunciado del ejercicio",
          "options": ["A", "B", "C", "D"],
          "correctIndex": 0,
          "correct": ["respuesta correcta"],
          "steps": ["paso 1", "paso 2", "paso 3"],
          "correctOrder": [0, 1, 2],
          "left": ["izquierda A", "izquierda B", "izquierda C"],
          "right": ["derecha A", "derecha B", "derecha C"],
          "correctPairs": [0, 1, 2],
          "explanation": "Explicación breve de por qué es correcto"
        }

        Reglas:
        - Usa solo los campos relevantes para cada tipo; los demás pueden omitirse o ser null.
        - quiz: 4 opciones, correctIndex apunta a la opción correcta.
        - fillBlank: el prompt contiene "______" donde falta la palabra; correct tiene 1-3 variantes aceptables.
        - reorder: 3-5 pasos; correctOrder es el orden correcto de los índices.
        - matching: 3 pares; correctPairs[i] = índice en right que empareja con left[i].
        - Las respuestas correctas deben estar inequívocamente determinadas por el contenido del nivel.
        - explanation: 1-2 frases en español que enseñan por qué.
        - Todo el contenido en español.
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
                    "solo \(valid.count)/\(exercises.count) ejercicios válidos")
            } catch {
                lastError = error
            }
        }
        throw lastError ?? GenerationError.invalidJSON("desconocido")
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
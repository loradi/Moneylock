import Foundation

struct PathSkeleton: Codable {
    var topic: String
    var levels: [LevelSkeleton]

    struct LevelSkeleton: Codable {
        var title: String
        var description: String
        var difficulty: Int
    }
}

enum GenerationError: LocalizedError {
    case modelNotLoaded
    case invalidJSON(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "El modelo de IA no está cargado."
        case .invalidJSON(let detail):
            return "La IA generó contenido inválido: \(detail)"
        case .emptyResult:
            return "La IA no generó contenido."
        }
    }
}

/// Genera el skeleton del path (niveles y lecciones) a partir del tema.
/// Fase 1: solo el árbol de niveles. Los ejercicios se generan on-demand.
actor PathGenerator {
    private let model: any ModelProvider
    private let maxAttempts = 2

    init(model: any ModelProvider) {
        self.model = model
    }

    func generatePath(topic: String) async throws -> LearningPath {
        let prompt = """
        Eres un tutor experto en pedagogía. Crea un plan de aprendizaje para el tema: "\(topic)".

        Genera 4 niveles de dificultad creciente (dificultad 1 a 4), cada uno con un título y una descripción breve de lo que se aprende en ese nivel.

        Responde ÚNICAMENTE con JSON válido, sin texto adicional, con esta estructura exacta:
        {"topic": "\(topic)", "levels": [{"title": "...", "description": "...", "difficulty": 1}, ...]}

        Reglas:
        - Exactamente 4 niveles.
        - difficulty va de 1 (básico) a 4 (avanzado).
        - Los títulos deben ser cortos (2-5 palabras).
        - Las descripciones deben ser de 1-2 frases en español.
        """

        var lastError: Error?
        for _ in 0..<maxAttempts {
            do {
                let raw = try await model.generate(
                    messages: [LLMMessage(role: .user, content: prompt)],
                    maxTokens: 800)
                let skeleton: PathSkeleton = try JSONParser.decode(PathSkeleton.self, from: raw)
                let path = buildPath(from: skeleton)
                guard !path.levels.isEmpty else {
                    lastError = GenerationError.emptyResult
                    continue
                }
                return path
            } catch {
                lastError = error
            }
        }
        throw lastError ?? GenerationError.invalidJSON("desconocido")
    }

    private func buildPath(from skeleton: PathSkeleton) -> LearningPath {
        let sortedLevels = skeleton.levels.sorted { $0.difficulty < $1.difficulty }
        let levels = sortedLevels.map { level in
            LearningPath.Level(
                title: level.title,
                description: level.description,
                difficulty: level.difficulty,
                lessons: [])
        }
        return LearningPath(topic: skeleton.topic.isEmpty ? "Aprendizaje" : skeleton.topic,
                            levels: levels)
    }
}
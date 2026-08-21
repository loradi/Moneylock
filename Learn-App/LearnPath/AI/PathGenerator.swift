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
            return "The AI model isn't loaded."
        case .invalidJSON(let detail):
            return "The AI generated invalid content: \(detail)"
        case .emptyResult:
            return "The AI didn't generate any content."
        }
    }
}

/// Generates the path skeleton (levels and lessons) from the topic.
/// Phase 1: level tree only. Exercises are generated on-demand.
actor PathGenerator {
    private let model: any ModelProvider
    private let maxAttempts = 2

    init(model: any ModelProvider) {
        self.model = model
    }

    func generatePath(topic: String) async throws -> LearningPath {
        let prompt = """
        You are an expert tutor in pedagogy. Create a learning plan for the topic: "\(topic)".

        Generate 4 levels of increasing difficulty (difficulty 1 to 4), each with a title and a brief description of what's learned at that level.

        Respond ONLY with valid JSON, no additional text, using this exact structure:
        {"topic": "\(topic)", "levels": [{"title": "...", "description": "...", "difficulty": 1}, ...]}

        Rules:
        - Exactly 4 levels.
        - difficulty ranges from 1 (basic) to 4 (advanced).
        - Titles should be short (2-5 words).
        - Descriptions should be 1-2 sentences in English.
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
        throw lastError ?? GenerationError.invalidJSON("unknown")
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
        return LearningPath(topic: skeleton.topic.isEmpty ? "Learning" : skeleton.topic,
                            levels: levels)
    }
}
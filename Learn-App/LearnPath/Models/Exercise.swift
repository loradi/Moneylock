import Foundation

enum ExerciseType: String, Codable, CaseIterable {
    case quiz
    case fillBlank
    case reorder
    case matching
}

struct Exercise: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let type: ExerciseType
    let prompt: String

    var options: [String]?
    var correctIndex: Int?

    var correct: [String]?

    var steps: [String]?
    var correctOrder: [Int]?

    var left: [String]?
    var right: [String]?
    var correctPairs: [Int]?

    var explanation: String

    init(type: ExerciseType, prompt: String,
         options: [String]? = nil, correctIndex: Int? = nil,
         correct: [String]? = nil,
         steps: [String]? = nil, correctOrder: [Int]? = nil,
         left: [String]? = nil, right: [String]? = nil,
         correctPairs: [Int]? = nil,
         explanation: String) {
        self.type = type
        self.prompt = prompt
        self.options = options
        self.correctIndex = correctIndex
        self.correct = correct
        self.steps = steps
        self.correctOrder = correctOrder
        self.left = left
        self.right = right
        self.correctPairs = correctPairs
        self.explanation = explanation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decode(ExerciseType.self, forKey: .type)
        prompt = try container.decode(String.self, forKey: .prompt)
        options = try container.decodeIfPresent([String].self, forKey: .options)
        correctIndex = try container.decodeIfPresent(Int.self, forKey: .correctIndex)
        correct = try container.decodeIfPresent([String].self, forKey: .correct)
        steps = try container.decodeIfPresent([String].self, forKey: .steps)
        correctOrder = try container.decodeIfPresent([Int].self, forKey: .correctOrder)
        left = try container.decodeIfPresent([String].self, forKey: .left)
        right = try container.decodeIfPresent([String].self, forKey: .right)
        correctPairs = try container.decodeIfPresent([Int].self, forKey: .correctPairs)
        explanation = try container.decodeIfPresent(String.self,
                                                    forKey: .explanation) ?? ""
    }
}

enum Answer: Equatable {
    case quiz(index: Int)
    case fillBlank(text: String)
    case reorder(order: [Int])
    case matching(pairs: [Int])
}

struct ValidationResult: Equatable {
    let isCorrect: Bool
    let expected: String
    let explanation: String
}
import Foundation

struct LearningPath: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var topic: String
    var levels: [Level]

    init(topic: String, levels: [Level]) {
        self.topic = topic
        self.levels = levels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        topic = try container.decode(String.self, forKey: .topic)
        levels = try container.decodeIfPresent([Level].self, forKey: .levels) ?? []
    }

    struct Level: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var title: String
        var description: String
        var difficulty: Int
        var lessons: [Lesson] = []

        init(title: String, description: String, difficulty: Int,
             lessons: [Lesson] = []) {
            self.title = title
            self.description = description
            self.difficulty = difficulty
            self.lessons = lessons
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            title = try container.decode(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self,
                                                        forKey: .description) ?? ""
            difficulty = try container.decodeIfPresent(Int.self,
                                                       forKey: .difficulty) ?? 1
            lessons = try container.decodeIfPresent([Lesson].self,
                                                    forKey: .lessons) ?? []
        }

        struct Lesson: Codable, Identifiable, Equatable {
            var id: UUID = UUID()
            var title: String
            var exercises: [Exercise] = []

            init(title: String, exercises: [Exercise] = []) {
                self.title = title
                self.exercises = exercises
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
                title = try container.decode(String.self, forKey: .title)
                exercises = try container.decodeIfPresent([Exercise].self,
                                                          forKey: .exercises) ?? []
            }
        }
    }
}
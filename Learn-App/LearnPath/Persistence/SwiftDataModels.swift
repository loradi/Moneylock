import Foundation
import SwiftData

@Model
final class PathRecord {
    var topic: String
    var createdAt: Date
    var isActive: Bool
    /// Niveles completados (índices). El nivel desbloqueado = último completado + 1.
    var completedLevels: [Int]
    /// Lecciones completadas por nivel: "nivelIndex.leccionIndex"
    var completedLessons: [String]
    var xp: Int
    /// JSON codificado del LearningPath completo (contenido generado).
    var pathData: Data

    init(topic: String, pathData: Data) {
        self.topic = topic
        self.createdAt = Date()
        self.isActive = true
        self.completedLevels = []
        self.completedLessons = []
        self.xp = 0
        self.pathData = pathData
    }
}

@Model
final class AppSettings {
    var modelLoadedOnce: Bool

    init(modelLoadedOnce: Bool = false) {
        self.modelLoadedOnce = modelLoadedOnce
    }
}
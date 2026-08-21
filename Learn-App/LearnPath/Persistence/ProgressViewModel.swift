import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ProgressViewModel {
    private let context: ModelContext
    private(set) var activePath: LearningPath?
    private(set) var activeRecord: PathRecord?
    private(set) var currentLevelIndex = 0

    private var record: PathRecord? { activeRecord }

    init(context: ModelContext) {
        self.context = context
        restoreActivePath()
    }

    // MARK: - Persistencia del path

    func savePath(_ path: LearningPath) throws {
        // Cierra el path activo anterior (solo uno activo a la vez).
        let fetch = FetchDescriptor<PathRecord>(
            predicate: #Predicate { $0.isActive == true })
        if let previous = try? context.fetch(fetch).first {
            previous.isActive = false
        }
        let encoder = JSONEncoder()
        let data = try encoder.encode(path)
        let record = PathRecord(topic: path.topic, pathData: data)
        context.insert(record)
        try context.save()
        activeRecord = record
        activePath = path
        currentLevelIndex = 0
    }

    func restoreActivePath() {
        let fetch = FetchDescriptor<PathRecord>(
            predicate: #Predicate { $0.isActive == true })
        guard let record = try? context.fetch(fetch).first else {
            activeRecord = nil
            activePath = nil
            return
        }
        activeRecord = record
        activePath = try? JSONDecoder().decode(LearningPath.self,
                                               from: record.pathData)
        currentLevelIndex = record.completedLevels.count
    }

    /// Desactiva el path actual (permite crear uno nuevo).
    func archiveActivePath() {
        activeRecord?.isActive = false
        try? context.save()
        activeRecord = nil
        activePath = nil
        currentLevelIndex = 0
    }

    // MARK: - Progreso

    var unlockedLevelIndex: Int {
        guard let record else { return 0 }
        return record.completedLevels.count
    }

    func isLevelUnlocked(_ index: Int) -> Bool {
        index <= unlockedLevelIndex
    }

    func isLevelCompleted(_ index: Int) -> Bool {
        record?.completedLevels.contains(index) ?? false
    }

    func isLessonCompleted(level: Int, lesson: Int) -> Bool {
        record?.completedLessons.contains("\(level).\(lesson)") ?? false
    }

    /// Marca una lección como completada. Si era la última del nivel,
    /// completa el nivel, desbloquea el siguiente y suma XP.
    func completeLesson(level: Int, lesson: Int, xp: Int) {
        guard let record, let path = activePath,
              path.levels.indices.contains(level) else { return }
        let key = "\(level).\(lesson)"
        guard !record.completedLessons.contains(key) else { return }
        record.completedLessons.append(key)
        record.xp += xp

        let levelLessonCount = path.levels[level].lessons.count
        let completedInLevel = record.completedLessons
            .filter { $0.hasPrefix("\(level).") }.count
        if completedInLevel >= levelLessonCount, levelLessonCount > 0 {
            if !record.completedLevels.contains(level) {
                record.completedLevels.append(level)
                record.xp += 20
            }
        }
        try? context.save()
        currentLevelIndex = record.completedLevels.count
    }

    /// Añade una lección generada al path activo (persistido).
    func addLesson(_ lesson: LearningPath.Level.Lesson, level: Int) throws {
        guard var path = activePath, path.levels.indices.contains(level) else { return }
        path.levels[level].lessons.append(lesson)
        activePath = path
        let encoder = JSONEncoder()
        record?.pathData = try encoder.encode(path)
        try context.save()
    }

    var totalXP: Int {
        record?.xp ?? 0
    }
}
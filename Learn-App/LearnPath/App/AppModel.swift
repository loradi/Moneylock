import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case loadingModel(String)
        case generatingPath
        case generatingLesson
        case ready
    }

    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?

    let engine: LLMEngine
    private var pathGenerator: PathGenerator?
    private var lessonGenerator: LessonGenerator?
    let progress: ProgressViewModel

    init(context: ModelContext) {
        self.engine = LLMEngine()
        self.progress = ProgressViewModel(context: context)
        if progress.activePath != nil {
            phase = .ready
        }
    }

    var hasActivePath: Bool {
        progress.activePath != nil
    }

    var activePath: LearningPath? {
        progress.activePath
    }

    // MARK: - Carga del modelo

    func ensureModelLoaded() async throws {
        if engine.isLoading { return }
        phase = .loadingModel("Cargando el modelo de IA…")
        defer {
            if case .loadingModel = phase { phase = .idle }
        }
        try await engine.load { status in
            Task { @MainActor in
                self.phase = .loadingModel(status)
            }
        }
        pathGenerator = PathGenerator(model: engine)
        lessonGenerator = LessonGenerator(model: engine)
        phase = .ready
    }

    // MARK: - Generación

    func generatePath(topic: String) async {
        do {
            try await ensureModelLoaded()
            phase = .generatingPath
            defer { phase = .ready }
            guard let pathGenerator else { return }
            let path = try await pathGenerator.generatePath(topic: topic)
            try progress.savePath(path)
        } catch {
            errorMessage = error.localizedDescription
            phase = .ready
        }
    }

    /// Genera la siguiente lección del nivel si falta alguna sin generar.
    func ensureLessonForCurrentLevel() async {
        guard let path = progress.activePath else { return }
        let levelIndex = progress.currentLevelIndex
        guard path.levels.indices.contains(levelIndex) else { return }
        let level = path.levels[levelIndex]
        guard level.lessons.isEmpty else { return }

        let lessonIndex = 0
        phase = .generatingLesson
        defer { phase = .ready }
        do {
            try await ensureModelLoaded()
            guard let lessonGenerator else { return }
            let lesson = try await lessonGenerator.generateLesson(
                topic: path.topic,
                levelTitle: level.title,
                difficulty: level.difficulty,
                lessonTitle: "Lección \(lessonIndex + 1)")
            try progress.addLesson(lesson, level: levelIndex)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    /// Regresa a la pantalla inicial (nuevo tema).
    func goHome() {
        progress.restoreActivePath()
        if progress.activePath == nil {
            phase = .idle
        } else {
            phase = .ready
        }
    }

    /// Cierra el path activo y permite crear uno nuevo.
    func startNewTopic() {
        progress.archiveActivePath()
        phase = .idle
    }

    /// Al terminar una lección, limpia la navegación para volver al path.
    func dismissLesson() {
        // La navegación se reinicia al volver a la raíz del NavigationStack.
        phase = .ready
    }
}
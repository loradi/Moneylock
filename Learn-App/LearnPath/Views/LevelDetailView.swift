import SwiftUI

struct LevelDetailView: View {
    @Bindable var model: AppModel
    let levelIndex: Int

    @State private var lessonToOpen: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let level = currentLevel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(level.title)
                            .font(.title.bold())
                        Text(level.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if level.lessons.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(level.lessons.enumerated()),
                                id: \.element.id) { lessonIndex, lesson in
                            lessonCard(lessonIndex: lessonIndex, lesson: lesson)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Nivel \(levelIndex + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $lessonToOpen) { lessonIndex in
            LessonView(model: model, levelIndex: levelIndex,
                       lessonIndex: lessonIndex)
        }
    }

    private var currentLevel: LearningPath.Level? {
        guard let path = model.activePath,
              path.levels.indices.contains(levelIndex) else { return nil }
        return path.levels[levelIndex]
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Este nivel aún no tiene lecciones.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await model.ensureLessonForCurrentLevel() }
            } label: {
                Label("Generar primera lección", systemImage: "sparkles")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func lessonCard(lessonIndex: Int, lesson: LearningPath.Level.Lesson) -> some View {
        let completed = model.progress.isLessonCompleted(level: levelIndex,
                                                         lesson: lessonIndex)
        return Button {
            lessonToOpen = lessonIndex
        } label: {
            HStack {
                Image(systemName: completed ? "checkmark.circle.fill" : "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(completed ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(lesson.exercises.count) ejercicios")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
}
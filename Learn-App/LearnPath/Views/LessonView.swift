import SwiftUI

struct LessonView: View {
    @Bindable var model: AppModel
    let levelIndex: Int
    let lessonIndex: Int

    @State private var currentExercise = 0
    @State private var answer: Answer?
    @State private var result: ValidationResult?
    @State private var showExplanation = false

    private var lesson: LearningPath.Level.Lesson? {
        guard let path = model.activePath,
              path.levels.indices.contains(levelIndex),
              path.levels[levelIndex].lessons.indices.contains(lessonIndex) else {
            return nil
        }
        return path.levels[levelIndex].lessons[lessonIndex]
    }

    var body: some View {
        Group {
            if let lesson {
                VStack(spacing: 0) {
                    progressHeader(count: lesson.exercises.count)
                    TabView(selection: $currentExercise) {
                        ForEach(Array(lesson.exercises.enumerated()), id: \.element.id) { index, exercise in
                            ExerciseView(
                                exercise: exercise,
                                answer: index == currentExercise ? answer : nil,
                                result: index == currentExercise ? result : nil,
                                onSubmit: { submitted in
                                    handleAnswer(submitted, exercise: exercise)
                                }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    footer
                }
            } else {
                ContentUnavailableView(
                    "Lección no disponible",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Esta lección ya no existe en el plan activo."))
            }
        }
        .navigationTitle(lesson?.title ?? "Lección")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled()
    }

    private func progressHeader(count: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(currentExercise + 1) de \(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ProgressView(value: Double(currentExercise + 1), total: Double(count))
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var footer: some View {
        Group {
            if let result {
                FeedbackView(
                    result: result,
                    isLast: currentExercise == (lesson?.exercises.count ?? 1) - 1,
                    onNext: next,
                    onFinish: finish
                )
            } else {
                Text("Responde para comprobar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    private func handleAnswer(_ submitted: Answer, exercise: Exercise) {
        answer = submitted
        result = ExerciseValidator.validate(exercise, answer: submitted)
        withAnimation(.spring(duration: 0.35)) {
            showExplanation = true
        }
    }

    private func next() {
        withAnimation {
            answer = nil
            result = nil
            showExplanation = false
            currentExercise += 1
        }
    }

    private func finish() {
        model.progress.completeLesson(level: levelIndex, lesson: lessonIndex, xp: 10)
        model.dismissLesson()
    }
}

// MARK: - Ejercicio (wrapper por tipo)

struct ExerciseView: View {
    let exercise: Exercise
    let answer: Answer?
    let result: ValidationResult?
    let onSubmit: (Answer) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(exercise.prompt)
                    .font(.title3.bold())
                    .multilineTextAlignment(.leading)

                switch exercise.type {
                case .quiz:
                    QuizExerciseView(exercise: exercise, onSubmit: onSubmit)
                case .fillBlank:
                    FillBlankExerciseView(exercise: exercise, onSubmit: onSubmit)
                case .reorder:
                    ReorderExerciseView(exercise: exercise, onSubmit: onSubmit)
                case .matching:
                    MatchingExerciseView(exercise: exercise, onSubmit: onSubmit)
                }
            }
            .padding()
        }
        .disabled(result != nil)
    }
}
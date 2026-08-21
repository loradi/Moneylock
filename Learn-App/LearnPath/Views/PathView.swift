import SwiftUI

struct PathView: View {
    @Bindable var model: AppModel
    @State private var selectedLevel: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                levelsList
            }
            .padding()
        }
        .navigationTitle(model.activePath?.topic ?? "Tu plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("\(model.progress.totalXP) XP")
                        .font(.subheadline.bold())
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Nuevo tema", systemImage: "plus.circle") {
                        model.startNewTopic()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Opciones")
            }
        }
        .navigationDestination(item: $selectedLevel) { index in
            LevelDetailView(model: model, levelIndex: index)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tu camino de aprendizaje")
                .font(.headline)
            Text("Completa los niveles en orden para desbloquear los siguientes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var levelsList: some View {
        VStack(spacing: 14) {
            ForEach(Array((model.activePath?.levels ?? []).enumerated()),
                    id: \.element.id) { index, level in
                LevelCard(
                    index: index,
                    level: level,
                    isUnlocked: model.progress.isLevelUnlocked(index),
                    isCompleted: model.progress.isLevelCompleted(index),
                    isCurrent: index == model.progress.currentLevelIndex
                ) {
                    selectedLevel = index
                }
            }
        }
    }
}

struct LevelCard: View {
    let index: Int
    let level: LearningPath.Level
    let isUnlocked: Bool
    let isCompleted: Bool
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(circleColor)
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isCompleted {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .background(Circle().fill(.white).frame(width: 20, height: 20))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Nivel \(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if isCurrent {
                            Text("EN CURSO")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: Capsule())
                                .foregroundStyle(.tint)
                        }
                    }
                    Text(level.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(level.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()

                Image(systemName: isUnlocked ? "chevron.right" : "lock.fill")
                    .foregroundStyle(isUnlocked ? Color.secondary : Color.gray.opacity(0.5))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .disabled(!isUnlocked)
        .opacity(isUnlocked ? 1 : 0.55)
    }

    private var circleColor: Color {
        if isCompleted { return Color.green }
        if isCurrent { return Color.accentColor }
        return isUnlocked ? Color.orange : Color.gray
    }

    private var icon: String {
        if isCompleted { return "checkmark" }
        if isCurrent { return "play.fill" }
        return isUnlocked ? "book.fill" : "lock.fill"
    }
}
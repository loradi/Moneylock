import SwiftUI
import SwiftData

struct TopicInputView: View {
    @Bindable var model: AppModel
    @State private var topic = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, options: .nonRepeating, value: isFocused)

            VStack(spacing: 8) {
                Text("¿Qué quieres aprender?")
                    .font(.largeTitle.bold())
                Text("Escribe cualquier tema y la IA creará tu plan de aprendizaje paso a paso.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Ej: Física cuántica, Historia de Roma, Swift…", text: $topic)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($isFocused)
                .submitLabel(.go)
                .onSubmit { generate() }

            Button(action: generate) {
                Label("Crear mi plan", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func generate() {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isFocused = false
        Task { await model.generatePath(topic: trimmed) }
    }
}

#Preview {
    TopicInputView(model: AppModel(context: try! ModelContainer(
        for: PathRecord.self, AppSettings.self).mainContext))
}
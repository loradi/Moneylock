import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var appModel: AppModel?

    var body: some View {
        Group {
            if let appModel {
                ContentView(model: appModel)
            } else {
                ProgressView("Inicializando…")
            }
        }
        .task {
            if appModel == nil {
                appModel = AppModel(context: context)
            }
        }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.hasActivePath {
                    PathView(model: model)
                } else {
                    TopicInputView(model: model)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay {
            if let status = loadingStatus(model.phase) {
                LoadingOverlay(text: status)
            }
        }
    }

    private func loadingStatus(_ phase: AppModel.Phase) -> String? {
        switch phase {
        case .loadingModel(let status): return status
        case .generatingPath: return "Generando tu plan de aprendizaje…"
        case .generatingLesson: return "Preparando la lección…"
        default: return nil
        }
    }
}

struct LoadingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(text)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
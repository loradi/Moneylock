import SwiftUI
import SwiftData

@main
struct LearnPathApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: PathRecord.self, AppSettings.self)
        } catch {
            fatalError("No se pudo crear el contenedor de datos: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
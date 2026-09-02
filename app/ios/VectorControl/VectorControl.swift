import AppIntents
import SwiftUI
import WidgetKit

struct OpenVectorAddPurchaseIntent: AppIntent {
  static var title: LocalizedStringResource = "Add with Vector"
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult & OpensIntent {
    .result(opensIntent: OpenURLIntent(URL(string: "moneylock://vector/add")!))
  }
}

struct VectorAddPurchaseControl: ControlWidget {
  static let kind = "com.moneylock.moneylock.add-with-vector"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: OpenVectorAddPurchaseIntent()) {
        Label("Add with Vector", systemImage: "plus.circle.fill")
      }
    }
    .displayName("Add with Vector")
    .description("Open Vector ready to record a purchase.")
  }
}

@main
struct VectorControlBundle: WidgetBundle {
  var body: some Widget {
    VectorAddPurchaseControl()
  }
}

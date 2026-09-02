import SwiftUI
import WidgetKit

struct VectorAddPurchaseControl: ControlWidget {
  static let kind = "com.moneylock.moneylock.add-with-vector"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: OpenVectorAddPurchaseIntent()) {
        Label("Add with Vector", systemImage: "lock.badge.plus")
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

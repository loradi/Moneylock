import AppIntents
import Foundation

/// Runs in the host app so Flutter can consume this one-shot request when the
/// app is foregrounded from Control Center.
@available(iOS 18.0, *)
struct OpenVectorAddPurchaseIntent: AppIntent {
  static var title: LocalizedStringResource = "Add with Vector"
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    UserDefaults.standard.set(true, forKey: "moneylock.vector.addPurchase")
    return .result()
  }
}

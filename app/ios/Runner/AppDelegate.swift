import Flutter
import UIKit
import Vision
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "moneylock/vision_ocr",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognizeText",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let image = UIImage(contentsOfFile: path),
            let cgImage = image.cgImage else {
        result(FlutterError(code: "INVALID_IMAGE", message: "Could not read receipt image.", details: nil))
        return
      }
      let request = VNRecognizeTextRequest { request, error in
        if let error {
          result(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
          return
        }
        let text = (request.results as? [VNRecognizedTextObservation] ?? [])
          .compactMap { $0.topCandidates(1).first?.string }
          .joined(separator: "\n")
        result(text)
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["en-US", "es-ES"]
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
          result(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
    let credentialsChannel = FlutterMethodChannel(
      name: "moneylock/sync_credentials",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    credentialsChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Credential store unavailable.", details: nil))
        return
      }
      switch call.method {
      case "readApiKey":
        result(self.readSyncApiKey() ?? "")
      case "writeApiKey":
        guard let args = call.arguments as? [String: Any],
              let apiKey = args["apiKey"] as? String else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing API key.", details: nil))
          return
        }
        self.writeSyncApiKey(apiKey, result: result)
      case "clearApiKey":
        self.clearSyncApiKey(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let vectorQuickActionChannel = FlutterMethodChannel(
      name: "moneylock/vector_quick_action",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    vectorQuickActionChannel.setMethodCallHandler { call, result in
      guard call.method == "takePendingAddPurchase" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let key = "moneylock.vector.addPurchase"
      let requested = UserDefaults.standard.bool(forKey: key)
      UserDefaults.standard.removeObject(forKey: key)
      result(requested)
    }
  }

  private let syncKeychainService = "com.moneylock.moneylock.sync"
  private let syncKeychainAccount = "api-key"

  private func syncKeychainQuery() -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: syncKeychainService,
      kSecAttrAccount: syncKeychainAccount,
    ]
  }

  private func readSyncApiKey() -> String? {
    var query = syncKeychainQuery()
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func writeSyncApiKey(_ apiKey: String, result: @escaping FlutterResult) {
    let data = Data(apiKey.utf8)
    let query = syncKeychainQuery()
    let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    let status: OSStatus
    if updateStatus == errSecItemNotFound {
      var insert = query
      insert[kSecValueData] = data
      insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(insert as CFDictionary, nil)
    } else {
      status = updateStatus
    }
    guard status == errSecSuccess else {
      result(FlutterError(code: "KEYCHAIN_WRITE_FAILED", message: "Could not store API key.", details: status))
      return
    }
    result(nil)
  }

  private func clearSyncApiKey(result: @escaping FlutterResult) {
    let status = SecItemDelete(syncKeychainQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      result(FlutterError(code: "KEYCHAIN_DELETE_FAILED", message: "Could not remove API key.", details: status))
      return
    }
    result(nil)
  }
}

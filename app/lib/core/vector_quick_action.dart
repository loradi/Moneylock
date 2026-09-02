import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum VectorQuickAction { addPurchase }

bool isVectorAddPurchaseLink(Uri uri) =>
    uri.scheme == 'moneylock' && uri.host == 'vector' && uri.path == '/add';

/// A tiny handoff between an OS-level action and Flutter navigation. The
/// pending value makes cold launches safe: Moneylock consumes it once its
/// router has a mounted navigator.
class VectorQuickActionController extends ChangeNotifier {
  VectorQuickAction? _pending;

  void requestAddPurchase() {
    _pending = VectorQuickAction.addPurchase;
    notifyListeners();
  }

  VectorQuickAction? takePending() {
    final action = _pending;
    _pending = null;
    return action;
  }
}

final vectorQuickActionController = VectorQuickActionController();

class VectorQuickActionBridge {
  static const _channel = MethodChannel('moneylock/vector_quick_action');

  static Future<bool> takePendingAddPurchase() async {
    try {
      return await _channel.invokeMethod<bool>('takePendingAddPurchase') ??
          false;
    } on PlatformException {
      return false;
    }
  }
}

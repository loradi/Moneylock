import 'package:flutter/foundation.dart';

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

import 'dart:async';

import 'package:app_links/app_links.dart';

import 'config.dart';
import '../features/add/add_transaction_flow.dart';

/// Handler de deep links `moneylock://add?...`.
///
/// Task 6 (router + UI) conectará el flujo real con los providers de la app
/// y llamará [startListening] tras construir el [AddTransactionFlow]. El
/// handler es agnóstico a la UI: parsea el scheme, ejecuta el flujo y emite
/// el [AddResult].
class DeepLinkHandler {
  DeepLinkHandler({required this.flow});
  final AddTransactionFlow flow;
  final AppLinks _links = AppLinks();
  final _handledLinks = <Uri, _HandledLink>{};

  static const _duplicateWindow = Duration(seconds: 2);

  /// Procesa un URI y retorna el resultado del flujo; null si el URI no es
  /// `moneylock://add`.
  Future<AddResult?> handle(Uri uri) async {
    if (uri.scheme != Config.appScheme || uri.host != 'add') return null;

    final now = DateTime.now();
    final previous = _handledLinks[uri];
    if (previous != null) {
      final completedAt = previous.completedAt;
      if (completedAt == null ||
          now.difference(completedAt) <= _duplicateWindow) {
        return previous.result;
      }
      _handledLinks.remove(uri);
    }

    final rawText = parseShortcutUrl(uri);
    final result = flow.run(rawText: rawText, source: 'shortcut');
    final handled = _HandledLink(result);
    _handledLinks[uri] = handled;
    try {
      return await result;
    } finally {
      handled.completedAt = DateTime.now();
    }
  }

  /// Link en frío (app abierta desde el atajo) + stream en caliente.
  Future<void> startListening({
    Future<Uri?> Function()? getInitialLink,
    Stream<Uri>? uriLinkStream,
  }) async {
    final initial = await (getInitialLink?.call() ?? _links.getInitialLink());
    if (initial != null) {
      unawaited(handle(initial).catchError((_) => null));
    }
    (uriLinkStream ?? _links.uriLinkStream).listen((uri) {
      unawaited(handle(uri).catchError((_) => null));
    });
  }
}

class _HandledLink {
  _HandledLink(this.result);

  final Future<AddResult?> result;
  DateTime? completedAt;
}

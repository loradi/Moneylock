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

  /// Procesa un URI y retorna el resultado del flujo; null si el URI no es
  /// `moneylock://add`.
  Future<AddResult?> handle(Uri uri) async {
    if (uri.scheme != Config.appScheme || uri.host != 'add') return null;
    final rawText = parseShortcutUrl(uri);
    return flow.run(rawText: rawText, source: 'shortcut');
  }

  /// Link en frío (app abierta desde el atajo) + stream en caliente.
  Future<void> startListening() async {
    final initial = await _links.getInitialLink();
    if (initial != null) {
      unawaited(handle(initial).catchError((_) => null));
    }
    _links.uriLinkStream.listen((uri) {
      unawaited(handle(uri).catchError((_) => null));
    });
  }
}
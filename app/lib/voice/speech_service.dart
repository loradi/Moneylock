import 'package:speech_to_text/speech_to_text.dart';

/// Excepción lanzada cuando el usuario deniega el permiso de reconocimiento
/// de voz (micrófono en iOS). Mensaje descriptivo listo para mostrarse.
class SpeechPermissionException implements Exception {
  final String message;
  SpeechPermissionException(this.message);

  @override
  String toString() => message;
}

/// Excepción lanzada cuando [SpeechToTextService.listen] se invoca sin una
/// inicialización exitosa previa.
class SpeechNotInitializedException implements Exception {
  final String message;
  SpeechNotInitializedException(this.message);

  @override
  String toString() => message;
}

/// Transcribe voz a texto usando el reconocedor nativo de Apple Speech
/// (speech_to_text 7.4.0, MIT). En iOS es on-device gratis (iOS 15+),
/// sin descarga de modelos ni servidores.
class SpeechToTextService {
  final SpeechToText _speech = SpeechToText();

  /// Inicializa el reconocedor. Lanza [SpeechPermissionException] si el
  /// usuario deniega el permiso (micrófono / reconocimiento de voz).
  Future<bool> init() async {
    final ok = await _speech.initialize();
    if (!ok) {
      throw SpeechPermissionException(
        'Speech recognition permission denied. '
        'Grant microphone + speech recognition access to Moneylock '
        'in Settings > Privacy.',
      );
    }
    return ok;
  }

  /// Escucha al micrófono y entrega el resultado final vía [onFinalResult].
  /// Requiere [init] exitoso antes.
  Future<void> listen(void Function(String text) onFinalResult) async {
    if (!_speech.isAvailable) {
      throw SpeechNotInitializedException(
        'SpeechToTextService.listen() called before a successful init().',
      );
    }
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) onFinalResult(result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(localeId: 'en_US'),
    );
  }

  /// Detiene la sesión de escucha activa (no hace nada si no hay ninguna).
  Future<void> stop() => _speech.stop();
}
import 'dart:io';
import 'package:flutter_whisper/flutter_whisper.dart' as whisper;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../core/config.dart';

const _minModelSize = 50 * 1024 * 1024; // ggml-base.en.bin ~= 75MB

class WhisperService {
  Future<Directory> _modelsDir() async {
    final dir = await getApplicationSupportDirectory();
    final models = Directory('${dir.path}/models');
    if (!await models.exists()) await models.create(recursive: true);
    return models;
  }

  Future<String> modelPath() async =>
      '${(await _modelsDir()).path}/${Config.whisperFilename}';

  Future<bool> isModelReady() async {
    final f = File(await modelPath());
    return f.existsSync() && f.lengthSync() >= _minModelSize;
  }

  /// Descarga reanudable (HTTP Range) del modelo a models/ggml-base.en.bin.
  /// Mismo patrón que [LlamaService.ensureModelDownloaded]: el .part se
  /// conserva entre intentos y se verifica la respuesta 206 contra el byte
  /// solicitado (servidores que ignoran Range reinician desde cero).
  Future<void> ensureModelDownloaded(void Function(double) onProgress) async {
    if (await isModelReady()) return;
    final file = File(await modelPath());
    final tmp = File('${file.path}.part');

    for (var attempt = 0; attempt < 2; attempt++) {
      var downloadedBytes = tmp.existsSync() ? await tmp.length() : 0;
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(Config.whisperUrl));
        if (downloadedBytes > 0) {
          request.headers['Range'] = 'bytes=$downloadedBytes-';
        }
        final response = await client.send(request);

        if (response.statusCode == 416 && downloadedBytes > 0) {
          // Rango inválido: .part corrupto. Borrar y reintentar desde cero.
          await tmp.delete();
          continue;
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          if (await tmp.exists()) await tmp.delete();
          throw Exception(
            'Whisper model download failed: HTTP ${response.statusCode}',
          );
        }

        if (response.statusCode == 206 && downloadedBytes > 0) {
          final range = response.headers['content-range'];
          final expected = 'bytes $downloadedBytes-';
          if (range == null || !range.startsWith(expected)) {
            downloadedBytes = 0;
          }
        }
        if (response.statusCode == 200) downloadedBytes = 0;

        final total = downloadedBytes + (response.contentLength ?? 0);
        var received = downloadedBytes;
        final sink = tmp.openWrite(
          mode: downloadedBytes > 0 ? FileMode.append : FileMode.write,
        );
        try {
          await for (final chunk in response.stream) {
            received += chunk.length;
            sink.add(chunk);
            if (total > 0) {
              onProgress((received / total).clamp(0.0, 1.0));
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        if (received < _minModelSize) {
          await tmp.delete();
          throw Exception('Whisper model download incomplete: $received bytes');
        }
        await tmp.rename(file.path);
        return;
      } finally {
        client.close();
      }
    }
    throw Exception('Whisper model download failed: HTTP 416');
  }

  /// Transcribe un audio local (wav/m4a/mp3) a texto en inglés.
  ///
  /// flutter_whisper 0.1.0 no expone initContext/fullTranscribe del brief:
  /// el singleton [whisper.Whisper] solo carga modelos de su catálogo
  /// (ggml-base.bin, URL propia del paquete). Para conservar la descarga
  /// propia vía Config.whisperUrl se usa [whisper.MethodChannelWhisperEngine]
  /// directamente con el path del modelo ya en disco.
  Future<String> transcribe(String audioPath) async {
    final engine = whisper.MethodChannelWhisperEngine();
    try {
      await engine.initialize(
        modelPath: await modelPath(),
        options: const whisper.WhisperOptions(language: 'en'),
      );
      final result = await engine.transcribeFile(audioPath);
      return result.text;
    } finally {
      await engine.dispose();
    }
  }
}
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:llama_cpp_dart/llama_cpp_dart.dart' as llama;
import 'package:path_provider/path_provider.dart';
import '../core/config.dart';
import 'llm_provider.dart';

const _minModelSize = 1024 * 1024 * 1024; // >= 1GB
const _maxTokens = 256;

class LlamaService {
  Future<Directory> _modelsDir() async {
    final dir = await getApplicationSupportDirectory();
    final models = Directory('${dir.path}/models');
    if (!await models.exists()) await models.create(recursive: true);
    return models;
  }

  Future<String> modelPath() async =>
      '${(await _modelsDir()).path}/${Config.modelFilename}';

  Future<bool> isModelReady() async {
    final f = File(await modelPath());
    return f.existsSync() && f.lengthSync() >= _minModelSize;
  }

  Future<void> ensureModelDownloaded(void Function(double) onProgress) async {
    if (await isModelReady()) return;
    final file = File(await modelPath());
    final tmp = File('${file.path}.part');

    for (var attempt = 0; attempt < 2; attempt++) {
      var downloadedBytes = tmp.existsSync() ? await tmp.length() : 0;
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(Config.modelUrl));
        if (downloadedBytes > 0) {
          request.headers['Range'] = 'bytes=$downloadedBytes-';
        }
        final response = await client.send(request);

        if (response.statusCode == 416 && downloadedBytes > 0) {
          // Rango inválido: el .part está corrupto/completo. Borrar y
          // reintentar desde cero.
          await tmp.delete();
          continue;
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          if (await tmp.exists()) await tmp.delete();
          throw Exception(
            'Model download failed: HTTP ${response.statusCode}',
          );
        }

        if (response.statusCode == 206 && downloadedBytes > 0) {
          // Validar que el server respondió exactamente desde el byte
          // pedido; si no, descartar lo parcial y reiniciar de cero.
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
          throw Exception('Model download incomplete: $received bytes');
        }
        await tmp.rename(file.path);
        return;
      } finally {
        client.close();
      }
    }
    throw Exception('Model download failed: HTTP 416');
  }
}

class LocalLlmProvider implements LlmProvider {
  final LlamaService service;
  LocalLlmProvider(this.service);

  llama.LlamaEngine? _engine;
  final _queue = <Future<void> Function()>[];
  bool _busy = false;

  @override
  Future<String> complete(
    String system,
    String user, {
    double temperature = 0.2,
  }) {
    return _enqueue(() async {
      final engine = await _ensureEngine();
      return _generate(engine, system, user, temperature)
          .timeout(const Duration(seconds: 60));
    });
  }

  /// Worker isolate interno del paquete: carga el modelo una sola vez y lo
  /// mantiene vivo. La temperatura se pasa por llamada (sampler), así que no
  /// hace falta cachear modelos por temperatura.
  Future<llama.LlamaEngine> _ensureEngine() async {
    final existing = _engine;
    if (existing != null) return existing;
    final engine = await llama.LlamaEngine.spawnFromProcess(
      modelParams: llama.ModelParams(path: await service.modelPath()),
      contextParams: llama.ContextParams.mobile(nCtx: 2048, nBatch: 512),
    );
    _engine = engine;
    return engine;
  }

  Future<String> _generate(
    llama.LlamaEngine engine,
    String system,
    String user,
    double temperature,
  ) async {
    final sampler = llama.SamplerParams(temperature: temperature);
    if (engine.modelChatTemplate != null) {
      // Chat template embebida en el GGUF (Qwen 2.5 instruct: chatml
      // <|im_start|>). Sesión fresca por llamada: complete() es stateless.
      final chat = await engine.createChat();
      try {
        chat.addSystem(system);
        chat.addUser(user);
        return await _collect(chat.generate(
          sampler: sampler,
          maxTokens: _maxTokens,
        ));
      } finally {
        await chat.dispose();
      }
    }
    // Modelo sin template: inyectar chatml manual como texto.
    final session = await engine.createSession();
    try {
      final prompt = '<|im_start|>system\n$system<|im_end|>\n'
          '<|im_start|>user\n$user<|im_end|>\n<|im_start|>assistant\n';
      return await _collect(session.generate(
        prompt: prompt,
        addSpecial: true,
        sampler: sampler,
        maxTokens: _maxTokens,
      ));
    } finally {
      await session.dispose();
    }
  }

  Future<String> _collect(Stream<llama.GenerationEvent> stream) async {
    final buf = StringBuffer();
    await for (final event in stream) {
      switch (event) {
        case llama.TokenEvent():
          buf.write(event.text);
        case llama.ShiftEvent():
          break;
        case llama.DoneEvent():
          if (event.reason is llama.StopUserAbort) {
            throw Exception('Generation aborted');
          }
          buf.write(event.trailingText);
      }
    }
    return buf.toString().trim();
  }

  Future<T> _enqueue<T>(Future<T> Function() fn) async {
    final completer = Completer<T>();
    _queue.add(() async {
      try {
        completer.complete(await fn());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    if (!_busy) _drain();
    return completer.future;
  }

  Future<void> _drain() async {
    _busy = true;
    while (_queue.isNotEmpty) {
      final fn = _queue.removeAt(0);
      await fn();
    }
    _busy = false;
  }
}

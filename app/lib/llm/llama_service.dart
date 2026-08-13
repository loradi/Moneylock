import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:llama_cpp_dart/llama_cpp_dart.dart' as llama;
import 'package:path_provider/path_provider.dart';
import 'package:typed_isolate/typed_isolate.dart';
import '../core/config.dart';
import 'llm_provider.dart';

const _minModelSize = 1024 * 1024 * 1024; // >= 1GB

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
    var downloadedBytes = tmp.existsSync() ? await tmp.length() : 0;

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(Config.modelUrl));
      if (downloadedBytes > 0) {
        request.headers['Range'] = 'bytes=$downloadedBytes-';
      }
      final response = await client.send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        if (await tmp.exists()) await tmp.delete();
        throw Exception('Model download failed: HTTP ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        // Sin soporte Range: descartar lo parcial y reiniciar de cero.
        downloadedBytes = 0;
      }

      final total = downloadedBytes + (response.contentLength ?? 0);
      var received = downloadedBytes;
      final sink = tmp.openWrite(
        mode: response.statusCode == 206 ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) onProgress(received / total);
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
    } finally {
      client.close();
    }
  }
}

class LlamaRequest {
  final int id;
  final String modelPath;
  final String system;
  final String user;
  final double temperature;
  const LlamaRequest({
    required this.id,
    required this.modelPath,
    required this.system,
    required this.user,
    required this.temperature,
  });
}

class LlamaResult {
  final int id;
  final String? text;
  final String? error;
  const LlamaResult({required this.id, this.text, this.error});
}

class LlamaWorker extends IsolateChild<LlamaResult, LlamaRequest> {
  LlamaWorker() : super(id: workerId);
  static const workerId = 'llama-worker';

  llama.Llama? _model;
  double? _temperature;
  Future<void> _chain = Future.value();

  @override
  void onData(LlamaRequest data) {
    _chain = _chain.then((_) => _handle(data));
  }

  Future<void> _handle(LlamaRequest data) async {
    try {
      sendToParent(LlamaResult(id: data.id, text: await _generate(data)));
    } catch (e) {
      sendToParent(LlamaResult(id: data.id, error: '$e'));
    }
  }

  Future<String> _generate(LlamaRequest data) async {
    if (_model == null || _temperature != data.temperature) {
      _model?.dispose();
      _model = llama.Llama(
        data.modelPath,
        samplerParams: llama.SamplerParams()..temp = data.temperature,
        contextParams: llama.ContextParams()..nPredict = 256,
      );
      _temperature = data.temperature;
    }
    final model = _model!;
    final prompt = '<|im_start|>system\n${data.system}<|im_end|>\n'
        '<|im_start|>user\n${data.user}<|im_end|>\n<|im_start|>assistant\n';
    model.clear();
    model.setPrompt(prompt);
    return (await model.generateCompleteText(maxTokens: 256)).trim();
  }
}

class LocalLlmProvider implements LlmProvider {
  final LlamaService service;
  LocalLlmProvider(this.service) {
    _parent.init();
    _parent.stream.listen(_onResult);
  }

  final _parent = IsolateParent<LlamaRequest, LlamaResult>();
  final Map<int, Completer<LlamaResult>> _pending = {};
  final _queue = <Future<void> Function()>[];
  int _nextId = 0;
  bool _busy = false;
  bool _workerSpawned = false;

  @override
  Future<String> complete(
      String system, String user, {double temperature = 0.2}) {
    return _enqueue(() async {
      await _ensureWorker();
      final id = _nextId++;
      final completer = Completer<LlamaResult>();
      _pending[id] = completer;
      _parent.sendToChild(
        id: LlamaWorker.workerId,
        data: LlamaRequest(
          id: id,
          modelPath: await service.modelPath(),
          system: system,
          user: user,
          temperature: temperature,
        ),
      );
      final LlamaResult result;
      try {
        result = await completer.future.timeout(const Duration(seconds: 60));
      } on TimeoutException {
        _pending.remove(id);
        rethrow;
      }
      if (result.error != null) throw Exception(result.error);
      return result.text!.trim();
    });
  }

  Future<void> _ensureWorker() async {
    if (_workerSpawned) return;
    await _parent.spawn(LlamaWorker());
    _workerSpawned = true;
  }

  void _onResult(LlamaResult result) {
    final completer = _pending.remove(result.id);
    completer?.complete(result);
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

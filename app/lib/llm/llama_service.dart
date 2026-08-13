import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:llama_cpp_dart/llama_cpp_dart.dart' as llama;
import 'package:path_provider/path_provider.dart';
import '../core/config.dart';
import 'llm_provider.dart';

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
    return f.existsSync() && f.lengthSync() > 1024 * 1024 * 1024; // >= 1GB
  }

  Future<void> ensureModelDownloaded(void Function(double) onProgress) async {
    if (await isModelReady()) return;
    final file = File(await modelPath());
    final tmp = File('${file.path}.part');
    final response = await http.Client().send(http.Request('GET', Uri.parse(Config.modelUrl)));
    if (response.statusCode != 200) {
      throw Exception('Model download failed: HTTP ${response.statusCode}');
    }
    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = tmp.openWrite();
    await for (final chunk in response.stream) {
      received += chunk.length;
      sink.add(chunk);
      if (total > 0) onProgress(received / total);
    }
    await sink.close();
    await tmp.rename(file.path);
  }
}

class LocalLlmProvider implements LlmProvider {
  final LlamaService service;
  LocalLlmProvider(this.service);

  llama.Llama? _model;
  double? _modelTemperature;
  final _queue = <Future<void> Function()>[];
  bool _busy = false;

  @override
  Future<String> complete(String system, String user, {double temperature = 0.2}) {
    return _enqueue(() async {
      final model = await _load(temperature);
      final prompt = '<|im_start|>system\n$system<|im_end|>\n'
          '<|im_start|>user\n$user<|im_end|>\n<|im_start|>assistant\n';
      model.clear();
      model.setPrompt(prompt);
      return (await model.generateCompleteText(maxTokens: 256)).trim();
    }).timeout(const Duration(seconds: 60));
  }

  Future<llama.Llama> _load(double temperature) async {
    if (_model != null && _modelTemperature == temperature) return _model!;
    _model?.dispose();
    final model = llama.Llama(
      await service.modelPath(),
      samplerParams: llama.SamplerParams()..temp = temperature,
      contextParams: llama.ContextParams()..nPredict = 256,
    );
    _model = model;
    _modelTemperature = temperature;
    return model;
  }

  Future<T> _enqueue<T>(Future<T> Function() fn) async {
    final completer = Completer<T>();
    _queue.add(() async {
      try { completer.complete(await fn()); } catch (e, st) { completer.completeError(e, st); }
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

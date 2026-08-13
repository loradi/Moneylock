# Moneylock MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir el MVP de Moneylock: app iOS en Flutter con mentor financiero LLM 100% on-device (categorización + presupuesto + chat + insights) y backend de sync mínimo.

**Architecture:** App Flutter offline-first con Drift/SQLite local, inferencia via `llama_cpp_dart` (Qwen 2.5 3B Q4) y STT via `flutter_whisper` (whisper.cpp). Captura por URL scheme (Apple Shortcut), voz y manual. Notificaciones locales (UNUserNotificationCenter). Backend FastAPI + SQLite solo para sync de respaldo.

**Tech Stack:** Flutter (iOS), Riverpod, go_router, Drift, llama_cpp_dart, flutter_whisper, Qwen 2.5 3B Instruct GGUF (Q4_K_M), whisper.cpp base.en, FastAPI + SQLAlchemy + Alembic + pytest.

**Spec:** `docs/superpowers/specs/2026-08-13-moneylock-design.md`

## Global Constraints

- **Nada pago**: sin APIs de pago, sin Firebase, sin APNs. Todo el LLM corre on-device; el backend jamás recibe texto para procesar por LLM.
- Modelos NO van en el bundle: se descargan en primer uso (Qwen ~1.9GB, whisper base.en ~145MB) a `Application Support` via `path_provider`.
- Modelo: `qwen2.5-3b-instruct-q4_k_m.gguf` desde `https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf`.
- Whisper: `ggml-base.en.bin` desde `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin`.
- Moneda: USD/CAD como texto, sin conversión. Montos con `double` (v1), formato con `NumberFormat.currency`.
- Categorías: `Coffee & Dining, Groceries, Transport, Entertainment, Shopping & E-commerce, Bills & Utilities, Health, Tech, Travel, Other`.
- Tones: `strict_ramsey` (default), `neutral_analyst`, `friendly_coach`.
- dedup: `sha256(normalize(raw_text) + timestamp)`; `normalize` = lower + trim + collapse spaces.
- Reglas mentor: gasto ≥80% del límite → `warning`; ≥100% → `alert`.
- UI estilo Cupertino. Textos de UI en inglés (mercado US/CA).
- Disclaimer insights (verbatim): "Educational information only, not financial advice."
- Commits por paso, mensajes convencionales en inglés (`feat:`, `test:`, `fix:`).
- Cada tarea con código termina con `flutter analyze` limpio y `flutter test` en verde.

---

### Task 0: Instalar Flutter y verificar toolchain iOS

**Files:** ninguno (setup del entorno)

- [ ] **Step 1: Instalar Flutter vía Homebrew**
  Run: `brew install --cask flutter`
  Expected: instalación completada, `flutter` en PATH (reabrir shell si no aparece).

- [ ] **Step 2: Verificar toolchain**
  Run: `flutter doctor`
  Expected: Flutter instalado; Xcode OK (Xcode 26.6 presente). Si pide CocoaPods:
  Run: `brew install cocoapods`

- [ ] **Step 3: Aceptar licencias Xcode**
  Run: `sudo xcodebuild -runFirstLaunch && sudo xcodebuild -license accept`
  Run: `flutter doctor` → sección Xcode en verde.

- [ ] **Step 4: Commit** (sin código; si hubo configuración del sistema, registrar en `docs/setup.md` los comandos usados)
  ```bash
  git add docs/setup.md
  git commit -m "docs: registrar setup de entorno (Flutter, Xcode)"
  ```

---

### Task 1: Skeleton Flutter + Drift schema + settings

**Files:**
- Create: `app/` (proyecto Flutter `moneylock`, solo iOS)
- Create: `app/lib/main.dart`, `app/lib/core/config.dart`, `app/lib/core/theme.dart`
- Create: `app/lib/data/tables.dart`, `app/lib/data/db.dart`
- Create: `app/test/db_test.dart`
- Modify: `app/pubspec.yaml`

**Interfaces:**
- Consumes: nada (tarea raíz).
- Produces:
  - `AppDatabase` (Drift): `settingsDao`; tablas `transactions, budgets, mentorMessages, agentMemories, settings`.
  - `SettingsDao.mentorTone()` → `Future<String>` (default `'strict_ramsey'`); `setMentorTone(String)` → `Future<void>`.
  - `Config.appScheme`, `Config.modelUrl`, `Config.modelFilename`, `Config.whisperUrl`, `Config.whisperFilename`.

- [ ] **Step 1: Crear el proyecto Flutter**
  ```bash
  flutter create app --org com.moneylock --project-name moneylock --platforms ios
  ```
  Expected: `app/` creado.

- [ ] **Step 2: Añadir dependencias**
  ```bash
  cd app && flutter pub add drift drift_flutter flutter_riverpod go_router crypto path_provider http intl
  cd app && flutter pub add --dev drift_dev build_runner
  ```

- [ ] **Step 3: Escribir el test que falla (DB roundtrip + tone)**

`app/test/db_test.dart`:
```dart
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('settings guarda y recupera mentor tone', () async {
    final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
    await db.settingsDao.setMentorTone('friendly_coach');
    expect(await db.settingsDao.mentorTone(), 'friendly_coach');
    await db.close();
  });
}
```

- [ ] **Step 4: Run test para verificar que falla**
  Run: `cd app && flutter test test/db_test.dart`
  Expected: FAIL — `db.dart` no existe.

- [ ] **Step 5: Implementar schema Drift**

`app/lib/data/tables.dart`:
```dart
import 'package:drift/drift.dart';

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get merchant => text().withDefault(const Constant(''))();
  TextColumn get category => text().withDefault(const Constant('Other'))();
  TextColumn get source => text()();
  TextColumn get rawText => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get dedupHash => text().unique()();
}

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category => text()();
  RealColumn get monthlyLimit => real()();
  TextColumn get period => text()(); // 'YYYY-MM'
  @override
  List<Set<Column>> get uniqueKeys => [{category, period}];
}

class MentorMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get role => text()(); // 'user' | 'mentor'
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
}

class AgentMemories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fact => text()();
  TextColumn get kind => text()();
  RealColumn get confidence => real()();
  DateTimeColumn get createdAt => dateTime()();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}
```

`app/lib/data/db.dart`:
```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'db.g.dart';

class SettingsDao {
  final AppDatabase db;
  SettingsDao(this.db);

  Future<String> mentorTone() async {
    final row = await (db.select(db.settings)
          ..where((s) => s.key.equals('mentor_tone')))
        .getSingleOrNull();
    return row?.value ?? 'strict_ramsey';
  }

  Future<void> setMentorTone(String tone) => db.into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: 'mentor_tone', value: tone));
}

@DriftDatabase(tables: [
  Transactions,
  Budgets,
  MentorMessages,
  AgentMemories,
  Settings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;

  late final SettingsDao settingsDao = SettingsDao(this);
}
```

`app/lib/core/config.dart`:
```dart
class Config {
  static const appScheme = 'moneylock';
  static const modelUrl = 'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf';
  static const modelFilename = 'qwen2.5-3b-instruct-q4_k_m.gguf';
  static const whisperUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin';
  static const whisperFilename = 'ggml-base.en.bin';
}
```

- [ ] **Step 6: Generar código Drift**
  Run: `cd app && dart run build_runner build --delete-conflicting-outputs`
  Expected: `db.g.dart` generado sin errores.

- [ ] **Step 7: Bootstrap mínimo**
  `main.dart`: `runApp` con un `HomeScreen` placeholder simple. `theme.dart`: `ThemeData(useMaterial3: true, pageTransitionsTheme: ...)` con `CupertinoPageTransitionsBuilder`. Router real en Task 6.

- [ ] **Step 8: Run tests**
  Run: `cd app && flutter test`
  Expected: PASS (db_test pasa; borrar/ajustar el widget_test.dart de la plantilla que referencia el counter).

- [ ] **Step 9: Lint + commit**
  Run: `cd app && flutter analyze` → Expected: sin errores.
  ```bash
  git add app/
  git commit -m "feat: flutter skeleton con schema Drift y settings"
  ```

---

### Task 2: Capa LLM — fallback_parser + LlamaService

**Files:**
- Create: `app/lib/llm/fallback_parser.dart`, `app/lib/llm/llama_service.dart`, `app/lib/llm/llm_provider.dart`
- Create: `app/test/fallback_parser_test.dart`

**Interfaces:**
- Consumes: `Config.modelUrl`, `Config.modelFilename` (Task 1).
- Produces:
  - `ParsedTransaction { double? amount; String currency; String? merchant; String? category; double confidence; }`
  - `ParsedTransaction? parseFallback(String rawText)` — regex/reglas, nunca lanza.
  - `abstract class LlmProvider { Future<String> complete(String system, String user, {double temperature}); }`
  - `class LocalLlmProvider implements LlmProvider` — envuelve `llama_cpp_dart`, serializa generaciones (1 a la vez), timeout 60s.
  - `class LlamaService` — `Future<bool> isModelReady()`, `Future<void> ensureModelDownloaded(void Function(double) onProgress)` (download reanudable con `http`, verifica tamaño ≥ 1GB), `Future<String> modelPath()`.
- El modelo se descarga a `Application Support/models/` (path_provider).

- [ ] **Step 1: Test que falla del parser fallback**

`app/test/fallback_parser_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/llm/fallback_parser.dart';

void main() {
  group('fallback parser', () {
    test('extrae monto y merchant de notificacion tipica', () {
      final p = parseFallback('Starbucks $12.50');
      expect(p!.amount, closeTo(12.50, 0.001));
      expect(p.merchant, 'Starbucks');
      expect(p.category, 'Coffee & Dining');
    });
    test('extrae monto con sufijo USD', () {
      final p = parseFallback('Apple.com 9.99 USD');
      expect(p!.amount, closeTo(9.99, 0.001));
      expect(p.currency, 'USD');
      expect(p.category, 'Shopping & E-commerce');
    });
    test('merchant desconocido -> Other, confianza baja', () {
      final p = parseFallback('FOOBARBAZ $3.00');
      expect(p!.category, 'Other');
      expect(p.confidence, lessThan(0.5));
    });
    test('sin monto -> null', () {
      expect(parseFallback('hello world'), isNull);
    });
    test('espacios multiples no rompen', () {
      final p = parseFallback('Uber  Trip  20.00  ');
      expect(p!.amount, closeTo(20.00, 0.001));
    });
  });
}
```

- [ ] **Step 2: Run test para verificar que falla**
  Run: `cd app && flutter test test/fallback_parser_test.dart`
  Expected: FAIL — fallback_parser.dart no existe.

- [ ] **Step 3: Implementar fallback_parser**

`app/lib/llm/fallback_parser.dart`:
```dart
class ParsedTransaction {
  final double? amount;
  final String currency;
  final String? merchant;
  final String? category;
  final double confidence;
  ParsedTransaction({this.amount, this.currency = 'USD', this.merchant,
      this.category, this.confidence = 0.4});
}

const _categoryCatalog = {
  'Coffee & Dining': ['starbucks', 'dunkin', 'chipotle', 'mcdonald', 'uber eats', 'doordash', 'grubhub', 'restaurant'],
  'Groceries': ['whole foods', 'trader joe', 'safeway', 'kroger', 'walmart'],
  'Transport': ['uber', 'lyft', 'shell', 'chevron', 'exxon'],
  'Entertainment': ['netflix', 'spotify', 'hulu', 'disney', 'movie'],
  'Shopping & E-commerce': ['amazon', 'apple.com', 'best buy', 'target', 'ebay', 'etsy'],
  'Bills & Utilities': ['comcast', 'xfinity', 'verizon', 'at&t', 'geico', 'progressive'],
  'Health': ['cvs', 'walgreens', 'pharmacy', 'doctor'],
  'Tech': ['icloud', 'google', 'dropbox', 'adobe', 'microsoft'],
  'Travel': ['airline', 'delta', 'united', 'american airlines', 'hotel', 'airbnb'],
};

String _normalize(String s) =>
    s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

double? _extractAmount(String raw) {
  final m = RegExp(r'\$\s?([0-9]+(?:\.[0-9]{1,2})?)').firstMatch(raw);
  if (m != null) return double.parse(m.group(1)!);
  final m2 = RegExp(r'([0-9]+(?:\.[0-9]{1,2})?)\s*(usd|cad|dollars|us|ca)\b', caseSensitive: false).firstMatch(raw);
  if (m2 != null) return double.parse(m2.group(1)!);
  return null;
}

String? _matchCategory(String normalized) {
  for (final entry in _categoryCatalog.entries) {
    for (final kw in entry.value) {
      if (normalized.contains(kw)) return entry.key;
    }
  }
  return null;
}

String? _cleanMerchant(String normalized) {
  final cleaned = normalized
      .replaceFirst(RegExp(r'\$?\s?[0-9]+(?:\.[0-9]{1,2})?\s*(usd|cad|dollars|us|ca)?.*$'), '')
      .replaceAll(RegExp(r'\b(usd|cad|dollars|us|ca)\b'), '')
      .trim();
  if (cleaned.isEmpty) return null;
  return cleaned.split(' ').map((w) => w.isEmpty ? w :
      '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

ParsedTransaction? parseFallback(String rawText) {
  final normalized = _normalize(rawText);
  final amount = _extractAmount(rawText);
  if (amount == null) return null;
  final category = _matchCategory(normalized);
  final currency = RegExp(r'\bcad\b').hasMatch(normalized) ? 'CAD' : 'USD';
  return ParsedTransaction(
    amount: amount,
    currency: currency,
    merchant: _cleanMerchant(normalized),
    category: category ?? 'Other',
    confidence: category == null ? 0.3 : 0.5,
  );
}
```

- [ ] **Step 4: Run test para verificar que pasa**
  Run: `cd app && flutter test test/fallback_parser_test.dart`
  Expected: PASS (5 tests).

- [ ] **Step 5: Implementar LlamaService y LlmProvider**

`app/lib/llm/llm_provider.dart`:
```dart
abstract class LlmProvider {
  Future<String> complete(String system, String user, {double temperature = 0.2});
}
```

`app/lib/llm/llama_service.dart`:
```dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../core/config.dart';

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
```

- [ ] **Step 6: Implementar LocalLlmProvider**

`app/lib/llm/llama_service.dart` (añadir al mismo archivo):
```dart
import 'dart:async';
import 'package:llama_cpp_dart/llama_cpp_dart.dart' as llama;
import 'llm_provider.dart';

class LocalLlmProvider implements LlmProvider {
  final LlamaService service;
  LocalLlmProvider(this.service);

  bool _loaded = false;
  final _queue = <Future<void> Function()>[];
  bool _busy = false;

  @override
  Future<String> complete(String system, String user, {double temperature = 0.2}) {
    return _enqueue(() async {
      final model = await _load();
      final prompt = '<|im_start|>system\n$system<|im_end|>\n'
          '<|im_start|>user\n$user<|im_end|>\n<|im_start|>assistant\n';
      var out = StringBuffer();
      await model.loop(prompt: prompt, maxToken: 256, temperature: temperature,
          callback: (r) { out.write(r); return false; });
      return out.toString().trim();
    }).timeout(const Duration(seconds: 60));
  }

  Future<llama.LlamaModel> _load() async {
    if (_loaded) return llama.getModel();
    await llama.loadModel(await service.modelPath());
    _loaded = true;
    return llama.getModel();
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
```
Nota: si `llama_cpp_dart` expone una API distinta (verificar el README del paquete tras `flutter pub add llama_cpp_dart`), adaptar `_load`/`complete` a la firma real — el contrato `LlmProvider` no cambia.

- [ ] **Step 7: Añadir llama_cpp_dart**
  Run: `cd app && flutter pub add llama_cpp_dart`
  Expected: dependencia añadida (ajustar iOS min target en `ios/Podfile`/`Podfile.properties` si el paquete lo exige).

- [ ] **Step 8: Lint + commit**
  Run: `cd app && flutter analyze` → sin errores.
  ```bash
  git add app/lib/llm app/test/fallback_parser_test.dart app/pubspec.yaml
  git commit -m "feat: fallback parser y servicio llama.cpp on-device"
  ```

---

### Task 3: CategorizerAgent (JSON estricto + fallback)

**Files:**
- Create: `app/lib/llm/prompts.dart`, `app/lib/llm/categorizer_agent.dart`
- Create: `app/test/categorizer_agent_test.dart`

**Interfaces:**
- Consumes: `LlmProvider.complete` (Task 2), `parseFallback`/`ParsedTransaction` (Task 2).
- Produces:
  - `class CategorizeResult { ParsedTransaction parsed; double confidence; }`
  - `class CategorizerAgent { CategorizerAgent(this.provider); Future<CategorizeResult> categorize(String rawText, {String source = 'manual'}); }`
  - `prompts.categorizerSystemPrompt` (String const).
  - Flujo: 1) llamada LLM; 2) extraer bloque `{...}` + `jsonDecode`; 3) validar (`amount` num > 0, `currency` ∈ {USD,CAD}, categoría en catálogo); 4) si algo falla → `parseFallback`; 5) confianza = min(LLM confidence, 1.0) o la del fallback.

- [ ] **Step 1: Test que falla**

`app/test/categorizer_agent_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/llm/categorizer_agent.dart';
import 'package:moneylock/llm/llm_provider.dart';

class _FakeLlm implements LlmProvider {
  final String response;
  _FakeLlm(this.response);
  @override
  Future<String> complete(String system, String user, {double temperature = 0.2}) async => response;
}

void main() {
  group('CategorizerAgent', () {
    test('parsea JSON valido del LLM', () async {
      final agent = CategorizerAgent(_FakeLlm(
        '{"amount": 45.5, "currency": "USD", "merchant": "Starbucks", "category": "Coffee & Dining", "confidence": 0.9}'));
      final r = await agent.categorize('Starbucks $45.50');
      expect(r.parsed.amount, closeTo(45.5, 0.001));
      expect(r.parsed.merchant, 'Starbucks');
      expect(r.parsed.category, 'Coffee & Dining');
      expect(r.confidence, closeTo(0.9, 0.001));
    });

    test('JSON invalido -> fallback determinista', () async {
      final agent = CategorizerAgent(_FakeLlm('I cannot parse that.'));
      final r = await agent.categorize('Starbucks $12.50');
      expect(r.parsed.amount, closeTo(12.5, 0.001));
      expect(r.parsed.category, 'Coffee & Dining');
      expect(r.parsed.merchant, 'Starbucks');
    });

    test('categoria fuera del catalogo -> fallback', () async {
      final agent = CategorizerAgent(_FakeLlm(
        '{"amount": 5, "currency": "USD", "merchant": "X", "category": "Nonsense", "confidence": 0.8}'));
      final r = await agent.categorize('X 5 USD');
      expect(r.parsed.category, isNot('Nonsense'));
    });
  });
}
```

- [ ] **Step 2: Run test para verificar que falla**
  Run: `cd app && flutter test test/categorizer_agent_test.dart`
  Expected: FAIL — categorizer_agent.dart no existe.

- [ ] **Step 3: Implementar prompts**

`app/lib/llm/prompts.dart`:
```dart
const categoryCatalog = [
  'Coffee & Dining', 'Groceries', 'Transport', 'Entertainment',
  'Shopping & E-commerce', 'Bills & Utilities', 'Health', 'Tech',
  'Travel', 'Other',
];

const categorizerSystemPrompt = '''
You extract purchase data from raw transaction text.
Return ONLY a JSON object with no markdown, no commentary:
{"amount": <number>, "currency": "USD"|"CAD", "merchant": "<string>",
 "category": "<one of: ${categoryCatalog.join(', ')}>", "confidence": <0.0-1.0>}
Rules:
- amount is a positive number in the currency unit stated.
- merchant is the company name only.
- If you cannot determine a field, use "" for merchant and "Other" for category.
Examples:
raw: "Starbucks $12.50" -> {"amount": 12.50, "currency": "USD", "merchant": "Starbucks", "category": "Coffee & Dining", "confidence": 0.95}
raw: "Apple.com 9.99 USD" -> {"amount": 9.99, "currency": "USD", "merchant": "Apple.com", "category": "Shopping & E-commerce", "confidence": 0.95}
raw: "UBER *TRIP 18.40 CAD" -> {"amount": 18.40, "currency": "CAD", "merchant": "Uber", "category": "Transport", "confidence": 0.95}
''';

const strictRamseyPrompt = '''
Eres un Mentor Financiero estricto, pragmatico y sin rodeos. Tu objetivo es hacer que el usuario cumpla sus metas financieras. Si el usuario gasta en cosas innecesarias o se acerca al limite de su presupuesto, debes llamarle la atencion directamente, senalarle el impacto en sus metas futuras y exigir un ajuste. Se firme, conciso y motivador desde la disciplina.
Respond in under 120 words. No emojis. Address the user as "you".
''';

const neutralAnalystPrompt = '''
You are a calm, data-driven financial analyst. Summarize the user's spending
against their budget with numbers and a neutral recommendation. Under 120 words.
Address the user as "you".
''';

const friendlyCoachPrompt = '''
You are a supportive financial coach. Point out spending patterns kindly,
encourage small improvements, and celebrate progress. Under 120 words.
Address the user as "you".
''';
```

- [ ] **Step 4: Implementar CategorizerAgent**

`app/lib/llm/categorizer_agent.dart`:
```dart
import 'dart:convert';
import 'fallback_parser.dart';
import 'llm_provider.dart';
import 'prompts.dart';

class CategorizeResult {
  final ParsedTransaction parsed;
  final double confidence;
  CategorizeResult(this.parsed, this.confidence);
}

class CategorizerAgent {
  final LlmProvider provider;
  CategorizerAgent(this.provider);

  Future<CategorizeResult> categorize(String rawText, {String source = 'manual'}) async {
    final raw = await provider.complete(categorizerSystemPrompt, rawText);
    final parsed = _parseJson(raw) ?? parseFallback(rawText);
    final confidence = (_parseJson(raw) ?? parseFallback(rawText)).confidence.clamp(0.0, 1.0);
    return CategorizeResult(parsed, confidence);
  }

  ParsedTransaction? _parseJson(String raw) {
    final match = RegExp(r'\{[^{}]*\}', dotAll: true).firstMatch(raw);
    if (match == null) return null;
    try {
      final map = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final amount = (map['amount'] as num?)?.toDouble();
      final currency = (map['currency'] as String?)?.toUpperCase();
      final merchant = (map['merchant'] as String?) ?? '';
      final category = (map['category'] as String?) ?? '';
      final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.5;
      if (amount == null || amount <= 0) return null;
      if (currency != null && currency != 'USD' && currency != 'CAD') return null;
      if (!categoryCatalog.contains(category)) return null;
      return ParsedTransaction(
        amount: amount,
        currency: currency ?? 'USD',
        merchant: merchant,
        category: category,
        confidence: confidence.clamp(0.0, 1.0),
      );
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 5: Run test para verificar que pasa**
  Run: `cd app && flutter test test/categorizer_agent_test.dart`
  Expected: PASS (3 tests).

- [ ] **Step 6: Lint + commit**
  Run: `cd app && flutter analyze` → sin errores.
  ```bash
  git add app/lib/llm/prompts.dart app/lib/llm/categorizer_agent.dart app/test/categorizer_agent_test.dart
  git commit -m "feat: categorizer agent con JSON estricto y fallback determinista"
  ```

---

### Task 4: MentorAgent + reglas de presupuesto + notificaciones locales

**Files:**
- Create: `app/lib/llm/mentor_agent.dart`
- Create: `app/lib/core/notifications.dart`
- Create: `app/lib/data/transactions_dao.dart`, `app/lib/data/budgets_dao.dart`, `app/lib/data/messages_dao.dart`, `app/lib/data/memories_dao.dart`
- Create: `app/test/mentor_rules_test.dart`
- Modify: `app/lib/data/db.dart` (registrar DAOs), `app/lib/main.dart` (permiso de notificaciones)

**Interfaces:**
- Consumes: `LlmProvider`, `prompts.*` (Task 3), `AppDatabase` (Task 1).
- Produces:
  - `enum Severity { info, warning, alert }`
  - `class MentorVerdict { Severity severity; String message; }`
  - `class MentorAgent { MentorAgent(this.provider, this.db); Future<MentorVerdict> evaluate({required String category, required double amount, required DateTime timestamp}); }`
  - Reglas puras: `Severity assessSpend(double spent, double? limit)`, `String mentorPromptFor(String tone)`.
  - `TransactionsDao`: `String dedupHash(String rawText, DateTime ts)`; `Future<({Transaction? transaction, bool inserted})> insertWithDedup(NewTransaction t)`; `Future<double> categorySpentThisPeriod(String category, String period)`; `Future<List<Transaction>> recent(int n)`.
  - `BudgetsDao`: `upsert(String category, double limit, String period)`, `limitsForPeriod(String period) → Map<String, double>`.
  - `MessagesDao`: `add(String role, String content)`, `watchAll() → Stream<List<MentorMessage>>`.
  - `MemoriesDao`: `add(String fact, String kind, double confidence)`.
  - `LocalNotifications`: `init()`, `show(String title, String body, Severity s)` (paquete `flutter_local_notifications`).

- [ ] **Step 1: Test que falla de las reglas**

`app/test/mentor_rules_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/llm/mentor_agent.dart';

void main() {
  group('assessSpend', () {
    test('bajo el 80% -> info', () {
      expect(assessSpend(350, 500), Severity.info);
    });
    test('en el 80% -> warning', () {
      expect(assessSpend(400, 500), Severity.warning);
    });
    test('sobre el limite -> alert', () {
      expect(assessSpend(500, 500), Severity.alert);
      expect(assessSpend(600, 500), Severity.alert);
    });
    test('sin presupuesto -> info', () {
      expect(assessSpend(100, null), Severity.info);
    });
  });
  group('mentorPromptFor', () {
    test('tono por defecto es strict', () {
      expect(mentorPromptFor('unknown_tone'), contains('estricto'));
    });
    test('neutral no contiene estricto', () {
      expect(mentorPromptFor('neutral_analyst'), isNot(contains('estricto')));
    });
  });
}
```

- [ ] **Step 2: Run test para verificar que falla**
  Run: `cd app && flutter test test/mentor_rules_test.dart`
  Expected: FAIL — mentor_agent.dart no existe.

- [ ] **Step 3: Implementar mentor_agent (reglas puras)**

`app/lib/llm/mentor_agent.dart`:
```dart
import 'prompts.dart';

enum Severity { info, warning, alert }

Severity assessSpend(double spent, double? limit) {
  if (limit == null) return Severity.info;
  if (spent >= limit) return Severity.alert;
  if (spent >= limit * 0.8) return Severity.warning;
  return Severity.info;
}

String mentorPromptFor(String tone) {
  switch (tone) {
    case 'neutral_analyst': return neutralAnalystPrompt;
    case 'friendly_coach': return friendlyCoachPrompt;
    default: return strictRamseyPrompt;
  }
}
```

- [ ] **Step 4: Implementar DAOs**

`app/lib/data/transactions_dao.dart`:
```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'db.dart';

class NewTransaction {
  final double amount; final String currency; final String merchant;
  final String category; final String source; final String rawText;
  final DateTime timestamp;
  NewTransaction({required this.amount, required this.currency,
    required this.merchant, required this.category, required this.source,
    required this.rawText, required this.timestamp});
}

class TransactionsDao {
  final AppDatabase db;
  TransactionsDao(this.db);

  String dedupHash(String rawText, DateTime ts) {
    final normalized = rawText.toLowerCase().trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return sha256.convert(utf8.encode('$normalized|${ts.toUtc().toIso8601String()}'))
        .toString();
  }

  Future<({Transaction? transaction, bool inserted})> insertWithDedup(NewTransaction t) async {
    final hash = dedupHash(t.rawText, t.timestamp);
    final existing = await (db.select(db.transactions)
          ..where((x) => x.dedupHash.equals(hash))).getSingleOrNull();
    if (existing != null) return (transaction: existing, inserted: false);
    final id = await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: t.amount, currency: t.currency, merchant: t.merchant,
      category: t.category, source: t.source, rawText: t.rawText,
      timestamp: t.timestamp, dedupHash: hash));
    final row = await (db.select(db.transactions)..where((x) => x.id.equals(id))).getSingle();
    return (transaction: row, inserted: true);
  }

  Future<double> categorySpentThisPeriod(String category, String period) async {
    final start = DateTime.parse('${period}-01T00:00:00');
    final end = DateTime(start.year, start.month + 1, 1);
    final rows = await (db.select(db.transactions)
          ..where((t) => t.category.equals(category) &
              t.timestamp.isBiggerOrEqualValue(start) &
              t.timestamp.isSmallerThanValue(end)))
        .get();
    return rows.fold(0.0, (sum, r) => sum + r.amount);
  }

  Future<List<Transaction>> recent(int n) async {
    final q = db.select(db.transactions)..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
    q.limit(n);
    return q.get();
  }
}
```

`app/lib/data/budgets_dao.dart`:
```dart
import 'package:drift/drift.dart';
import 'db.dart';

class BudgetsDao {
  final AppDatabase db;
  BudgetsDao(this.db);

  Future<void> upsert(String category, double limit, String period) =>
      db.into(db.budgets).insertOnConflictUpdate(BudgetsCompanion.insert(
          category: category, monthlyLimit: limit, period: period));

  Future<Map<String, double>> limitsForPeriod(String period) async {
    final rows = await (db.select(db.budgets)
          ..where((b) => b.period.equals(period))).get();
    return {for (final r in rows) r.category: r.monthlyLimit};
  }
}
```

`app/lib/data/messages_dao.dart`:
```dart
import 'package:drift/drift.dart';
import 'db.dart';

class MessagesDao {
  final AppDatabase db;
  MessagesDao(this.db);

  Future<void> add(String role, String content) =>
      db.into(db.mentorMessages).insert(MentorMessagesCompanion.insert(
          role: role, content: content, createdAt: DateTime.now()));

  Stream<List<MentorMessage>> watchAll() {
    final q = db.select(db.mentorMessages)
      ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]);
    return q.watch();
  }
}
```

`app/lib/data/memories_dao.dart`:
```dart
import 'package:drift/drift.dart';
import 'db.dart';

class MemoriesDao {
  final AppDatabase db;
  MemoriesDao(this.db);

  Future<void> add(String fact, String kind, double confidence) =>
      db.into(db.agentMemories).insert(AgentMemoriesCompanion.insert(
          fact: fact, kind: kind, confidence: confidence, createdAt: DateTime.now()));
}
```

Registrar en `db.dart`: `late final TransactionsDao transactionsDao = TransactionsDao(this);` y análogos para budgets/messages/memories.

- [ ] **Step 5: Implementar MentorAgent (evaluación con LLM)**

`app/lib/llm/mentor_agent.dart` (añadir):
```dart
import 'package:moneylock/data/db.dart';
import 'llm_provider.dart';

class MentorVerdict {
  final Severity severity;
  final String message;
  MentorVerdict(this.severity, this.message);
}

class MentorAgent {
  final LlmProvider provider;
  final AppDatabase db;
  MentorAgent(this.provider, this.db);

  Future<MentorVerdict> evaluate({
    required String category,
    required double amount,
    required DateTime timestamp,
  }) async {
    final period = '${timestamp.year.toString().padLeft(4, '0')}-${timestamp.month.toString().padLeft(2, '0')}';
    final limits = await db.budgetsDao.limitsForPeriod(period);
    final spent = await db.transactionsDao.categorySpentThisPeriod(category, period);
    final limit = limits[category];
    final severity = assessSpend(spent, limit);

    final tone = await db.settingsDao.mentorTone();
    final recent = await db.transactionsDao.recent(5);
    final recentText = recent.isEmpty ? 'No prior transactions.'
        : recent.map((t) => '${t.merchant.isEmpty ? t.category : t.merchant}: \$${t.amount.toStringAsFixed(2)} (${t.category})').join('\n');

    final context = 'Category: $category\n'
        'New amount: \$${amount.toStringAsFixed(2)}\n'
        'Spent this month in $category: \$${spent.toStringAsFixed(2)}\n'
        'Monthly limit for $category: ${limit == null ? 'none' : '\$${limit.toStringAsFixed(2)}'}\n'
        'Recent transactions:\n$recentText';

    String message;
    if (severity == Severity.info && limit == null) {
      message = 'Transaction recorded: \$${amount.toStringAsFixed(2)} in $category.';
    } else {
      try {
        message = await provider.complete(mentorPromptFor(tone), context);
      } catch (_) {
        message = severity == Severity.alert
            ? 'You are over budget on $category (${spent.toStringAsFixed(2)}). Tighten up.'
            : severity == Severity.warning
            ? 'You have used ${(spent / limit! * 100).toStringAsFixed(0)}% of your $category budget.'
            : 'Transaction recorded in $category.';
      }
    }
    return MentorVerdict(severity, message);
  }
}
```

- [ ] **Step 6: Implementar LocalNotifications**

`app/lib/core/notifications.dart`:
```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../llm/mentor_agent.dart';

class LocalNotifications {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const settings = InitializationSettings(
        iOS: DarwinInitializationSettings(requestAlertPermission: true,
            requestBadgePermission: true, requestSoundPermission: true));
    await _plugin.initialize(settings);
  }

  Future<void> show(String title, String body, Severity severity) =>
      _plugin.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body,
          const NotificationDetails(iOS: DarwinNotificationDetails(badgeNumber: 1)),
          payload: severity.name);
}
```
Run: `cd app && flutter pub add flutter_local_notifications`

- [ ] **Step 7: Tests de reglas pasan**
  Run: `cd app && flutter test test/mentor_rules_test.dart`
  Expected: PASS.

- [ ] **Step 8: Lint + commit**
  Run: `cd app && flutter analyze` → sin errores.
  ```bash
  git add app/lib/llm/mentor_agent.dart app/lib/core/notifications.dart app/lib/data
  git add app/test/mentor_rules_test.dart app/pubspec.yaml
  git commit -m "feat: mentor agent, reglas de presupuesto y notificaciones locales"
  ```

---

### Task 5: Captura — URL scheme (Shortcut), voz (whisper), entrada manual

**Files:**
- Create: `app/lib/features/add/add_transaction_flow.dart` (orquestador: captura → categoriza → dedup → guarda → mentor → notifica)
- Create: `app/lib/voice/whisper_service.dart`
- Create: `app/lib/features/add/voice_button.dart`
- Create: `app/lib/features/add/manual_form.dart`
- Create: `docs/apple-shortcut.md`
- Modify: `app/ios/Runner/Info.plist` (CFBundleURLTypes), `app/lib/main.dart` (deep link handling + `LocalNotifications.init`), `app/lib/core/router.dart` (se crea en Task 6; aquí el handler del scheme)

**Interfaces:**
- Consumes: `CategorizerAgent` (Task 3), `MentorAgent`/`MessagesDao` (Task 4), `TransactionsDao.insertWithDedup` (Task 4), `LocalNotifications` (Task 4), `Config.appScheme` (Task 1).
- Produces:
  - `class AddTransactionFlow { AddTransactionFlow({required this.categorizer, required this.mentor, required this.db, required this.notifications}); Future<AddResult> run({required String rawText, required String source, DateTime? timestamp}); }`
  - `class AddResult { bool inserted; MentorVerdict? verdict; String? error; }`
  - `class WhisperService { Future<bool> isModelReady(); Future<void> ensureModelDownloaded(void Function(double) onProgress); Future<String> transcribe(String audioPath); }` (modelo base.en en Application Support/models/).
  - `String parseShortcutUrl(Uri uri)` → devuelve el rawText normalizado `'$merchant $amount USD'` o lanza `FormatException`. Params: `amount`, `merchant`, `category` (opcional), `date` (ISO opcional).

- [ ] **Step 1: Test que falla del parseo de URL del Shortcut**

`app/test/shortcut_url_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/add/add_transaction_flow.dart';

void main() {
  test('parsea URL del shortcut', () {
    final u = Uri.parse('moneylock://add?amount=45.50&merchant=Starbucks');
    expect(parseShortcutUrl(u), 'Starbucks 45.50 USD');
  });
  test('sin amount lanza FormatException', () {
    expect(() => parseShortcutUrl(Uri.parse('moneylock://add?merchant=X')),
        throwsFormatException);
  });
}
```

- [ ] **Step 2: Run test para verificar que falla**
  Run: `cd app && flutter test test/shortcut_url_test.dart`
  Expected: FAIL — add_transaction_flow.dart no existe.

- [ ] **Step 3: Implementar AddTransactionFlow + parseShortcutUrl**

`app/lib/features/add/add_transaction_flow.dart`:
```dart
import '../../data/db.dart';
import '../../data/transactions_dao.dart';
import '../../llm/categorizer_agent.dart';
import '../../llm/mentor_agent.dart';
import '../../core/notifications.dart';

class AddResult {
  final bool inserted;
  final MentorVerdict? verdict;
  final String? error;
  AddResult({required this.inserted, this.verdict, this.error});
}

String parseShortcutUrl(Uri uri) {
  final amount = uri.queryParameters['amount'];
  final merchant = uri.queryParameters['merchant'];
  if (amount == null || double.tryParse(amount) == null) {
    throw FormatException('Missing or invalid amount: $amount');
  }
  return '$merchant $amount USD';
}

class AddTransactionFlow {
  final CategorizerAgent categorizer;
  final MentorAgent mentor;
  final AppDatabase db;
  final LocalNotifications notifications;
  AddTransactionFlow({required this.categorizer, required this.mentor,
      required this.db, required this.notifications});

  Future<AddResult> run({required String rawText, required String source, DateTime? timestamp}) async {
    final ts = timestamp ?? DateTime.now();
    try {
      final result = await categorizer.categorize(rawText, source: source);
      final parsed = result.parsed;
      if (parsed.amount == null) {
        return AddResult(inserted: false, error: 'Could not extract amount');
      }
      final outcome = await db.transactionsDao.insertWithDedup(NewTransaction(
        amount: parsed.amount, currency: parsed.currency,
        merchant: parsed.merchant ?? '', category: parsed.category ?? 'Other',
        source: source, rawText: rawText, timestamp: ts));
      if (!outcome.inserted) {
        return AddResult(inserted: false);
      }
      final verdict = await mentor.evaluate(
          category: outcome.transaction!.category,
          amount: outcome.transaction!.amount,
          timestamp: ts);
      await db.messagesDao.add('mentor', verdict.message);
      final title = switch (verdict.severity) {
        Severity.alert => 'Over budget',
        Severity.warning => 'Budget warning',
        Severity.info => 'Transaction recorded',
      };
      await notifications.show(title, verdict.message, verdict.severity);
      return AddResult(inserted: true, verdict: verdict);
    } catch (e) {
      return AddResult(inserted: false, error: e.toString());
    }
  }
}
```

- [ ] **Step 4: Run tests**
  Run: `cd app && flutter test test/shortcut_url_test.dart`
  Expected: PASS (2 tests).

- [ ] **Step 5: Registrar el URL scheme en Info.plist**

`app/ios/Runner/Info.plist` — añadir antes de `</dict>`:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.moneylock.app</string>
    <key>CFBundleURLSchemes</key>
    <array><string>moneylock</string></array>
  </dict>
</array>
```
Además añadir en `Info.plist` (audio + notas de transacción):
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Moneylock uses the microphone to record voice transactions.</string>
```

- [ ] **Step 6: Handler del deep link en main.dart**
  Usar `go_router` `initialLocation` desde `AppLinks`/`uni_links` (Run: `cd app && flutter pub add app_links`):
  - `onAppStart: getInitialLink` → si empieza con `moneylock://add`, ejecutar `AddTransactionFlow.run(rawText: parseShortcutUrl(uri), source: 'shortcut')`.
  - Suscripción a `uriLinkStream` para llamadas en caliente.
  - En `main()`: `await notifications.init();` antes de `runApp`.

- [ ] **Step 7: Implementar WhisperService**

`app/lib/voice/whisper_service.dart`:
```dart
import 'dart:io';
import 'package:flutter_whisper/flutter_whisper.dart' as whisper;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../core/config.dart';

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
    return f.existsSync() && f.lengthSync() > 50 * 1024 * 1024; // >= 50MB
  }

  Future<void> ensureModelDownloaded(void Function(double) onProgress) async {
    if (await isModelReady()) return;
    final file = File(await modelPath());
    final tmp = File('${file.path}.part');
    final response = await http.Client().send(
        http.Request('GET', Uri.parse(Config.whisperUrl)));
    if (response.statusCode != 200) {
      throw Exception('Whisper model download failed: HTTP ${response.statusCode}');
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

  Future<String> transcribe(String audioPath) async {
    final ctx = whisper.initContext(await modelPath());
    final result = whisper.fullTranscribe(ctx, audioPath, 'en');
    return result.text;
  }
}
```
Nota: si la API de `flutter_whisper` difiere, adaptar `transcribe` al README real del paquete (Run: `cd app && flutter pub add flutter_whisper`). `VoiceButton` (en Task 6) usa `record` para grabar audio m4a.

- [ ] **Step 8: Docs del Shortcut**

`docs/apple-shortcut.md` — instrucciones paso a paso:
1. Crear atajo "Add Transaction" en Shortcuts.
2. Usar acción "Ask for Input" (amount, merchant).
3. Acción "Open URLs" con `moneylock://add?amount=...&merchant=...` (construido con "Text" + "URL").
4. Nota: opcional capturar recibo de Apple Pay con "Show Notification" manual; la app soporta `category` y `date` opcionales.
5. Ejemplo JSON del atajo exportado (código del plist de atajos, opcional).

- [ ] **Step 9: Lint + commit**
  Run: `cd app && flutter analyze` → sin errores.
  ```bash
  git add app/lib/features/add app/lib/voice docs/apple-shortcut.md app/ios/Runner/Info.plist
  git commit -m "feat: captura por URL scheme, whisper y flujo de transaccion"
  ```

---

### Task 6: UI — Dashboard, Chat, Insights, Settings (Cupertino)

**Files:**
- Create: `app/lib/core/router.dart` (go_router, Cupertino transitions)
- Create: `app/lib/features/dashboard/dashboard_screen.dart` (+ `budget_bar.dart`)
- Create: `app/lib/features/chat/chat_screen.dart`
- Create: `app/lib/features/insights/insights_screen.dart` (+ `insights_agent.dart`)
- Create: `app/lib/features/settings/settings_screen.dart`
- Create: `app/lib/features/add/voice_button.dart` (grabación con `record`)
- Create: `app/lib/providers.dart` (Riverpod providers: `appDatabaseProvider`, `llmProviderProvider`, `categorizerProvider`, `mentorProvider`, `addFlowProvider`, `transactionsStreamProvider`, `messagesStreamProvider`, `budgetSummaryProvider`, `insightsProvider`)
- Modify: `app/lib/main.dart` (ProviderScope + router)

**Interfaces:**
- Consumes: DAOs + agents (Tasks 2-5).
- Produces:
  - `class BudgetSummary { double totalSpent; double totalLimit; Map<String, double> byCategory; }` — `budgetSummaryProvider` (watch stream de transactions + límites del período actual).
  - `class InsightCapsule { String title; String body; }` — `InsightsAgent.generate(summary) → List<InsightCapsule>`; cada cuerpo termina con el disclaimer verbatim: "Educational information only, not financial advice."
  - `routes`: `/` → shell con bottom tabs (Dashboard, Chat, Insights, Settings).

- [ ] **Step 1: Test que falla de InsightsAgent**

`app/test/insights_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/insights/insights_agent.dart';

void main() {
  test('genera capsula por categoria dominante con disclaimer', () {
    final caps = generateInsights(BudgetSummary(
      totalSpent: 1000, totalLimit: 2000,
      byCategory: {'Coffee & Dining': 600, 'Transport': 400}));
    expect(caps, isNotEmpty);
    final body = caps.first.body;
    expect(body, contains('Educational information only, not financial advice.'));
  });
  test('sin gasto -> capsula unica generica', () {
    final caps = generateInsights(
        BudgetSummary(totalSpent: 0, totalLimit: 0, byCategory: {}));
    expect(caps.length, 1);
  });
}
```

- [ ] **Step 2: Run test para verificar que falla**
  Run: `cd app && flutter test test/insights_test.dart`
  Expected: FAIL — insights_agent.dart no existe.

- [ ] **Step 3: Implementar InsightsAgent**

`app/lib/features/insights/insights_agent.dart`:
```dart
import 'package:moneylock/features/dashboard/dashboard_screen.dart';

const disclaimer = 'Educational information only, not financial advice.';

class InsightCapsule {
  final String title;
  final String body;
  InsightCapsule(this.title, this.body);
}

List<InsightCapsule> generateInsights(BudgetSummary s) {
  if (s.totalSpent <= 0) {
    return [InsightCapsule('Start tracking',
        'Add your first transaction to unlock spending insights. $disclaimer')];
  }
  final top = s.byCategory.entries
      .map((e) => (cat: e.key, pct: e.value / s.totalSpent))
      .toList()
    ..sort((a, b) => b.pct.compareTo(a.pct));
  final dominant = top.first;
  final pct = (dominant.pct * 100).toStringAsFixed(0);
  return [
    InsightCapsule('${dominant.cat} dominates',
        '$pct% of your spending went to ${dominant.cat} this month. '
        'Households in this pattern typically respond to category limits. '
        'Consider a monthly cap to retake control. $disclaimer'),
    InsightCapsule('Budget health',
        s.totalLimit > 0
            ? 'You have used ${(s.totalSpent / s.totalLimit * 100).toStringAsFixed(0)}% '
              'of your total monthly budget. $disclaimer'
            : 'Set category budgets in Settings to track limit health. $disclaimer'),
  ];
}
```

- [ ] **Step 4: Run test para verificar que pasa**
  Run: `cd app && flutter test test/insights_test.dart`
  Expected: PASS (2 tests).

- [ ] **Step 5: Implementar providers (Riverpod)**

`app/lib/providers.dart` — patrón:
```dart
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(name: 'moneylock'));
  ref.onDispose(db.close);
  return db;
});

final llamaServiceProvider = Provider<LlamaService>((ref) => LlamaService());
final llmProviderProvider = Provider<LlmProvider>((ref) =>
    LocalLlmProvider(ref.watch(llamaServiceProvider)));
final categorizerProvider = Provider<CategorizerAgent>((ref) =>
    CategorizerAgent(ref.watch(llmProviderProvider)));
final mentorProvider = Provider<MentorAgent>((ref) => MentorAgent(
    ref.watch(llmProviderProvider), ref.watch(appDatabaseProvider)));
final addFlowProvider = Provider<AddTransactionFlow>((ref) => AddTransactionFlow(
    categorizer: ref.watch(categorizerProvider),
    mentor: ref.watch(mentorProvider),
    db: ref.watch(appDatabaseProvider),
    notifications: LocalNotifications()));

final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final q = db.select(db.transactions)
    ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
  return q.watch();
});

final messagesStreamProvider = StreamProvider<List<MentorMessage>>((ref) =>
    ref.watch(appDatabaseProvider).messagesDao.watchAll());

final budgetSummaryProvider = StreamProvider<BudgetSummary>((ref) async* {
  final db = ref.watch(appDatabaseProvider);
  await for (final _ in db.select(db.transactions).watch()) {
    final now = DateTime.now();
    final period = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final limits = await db.budgetsDao.limitsForPeriod(period);
    final rows = await db.select(db.transactions).get();
    final byCategory = <String, double>{};
    for (final t in rows) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
    }
    final totalSpent = byCategory.values.fold(0.0, (a, b) => a + b);
    final totalLimit = limits.values.fold(0.0, (a, b) => a + b);
    yield BudgetSummary(totalSpent: totalSpent, totalLimit: totalLimit, byCategory: byCategory);
  }
});
```
Nota: para simplificar, `budgetSummaryProvider` puede implementarse con `FutureProvider.family` que se refresca al insertar; se acepta la variante funcional del subagente si el stream doble consulta complica.

- [ ] **Step 6: Dashboard (Cupertino)**
  - `DashboardScreen`: header con "Today"/"This month" total (formato `NumberFormat.currency`), lista de las categorías con `BudgetBar` (progress: spent/limit, color: green <80%, orange 80-99%, red ≥100%), y lista de transacciones recientes (merchant, categoría, monto, fecha).
  - `BudgetBar` widget: `LinearProgressIndicator` estilo Cupertino + label `spent / limit`.
  - Botón flotante (+) → bottom sheet con las dos entradas: `ManualForm` y `VoiceButton`.

- [ ] **Step 7: Chat**
  - `ChatScreen`: `ListView` con burbujas (mentor = gris, user = azul), campo de texto + envío.
  - Envío: `db.messagesDao.add('user', text)`; si el texto contiene un monto (regex), ejecutar `addFlow.run(rawText: text, source: 'manual')`; si no, llamar `provider.complete(mentorPromptFor(tone), text)`, persistir como 'mentor', y `scrollController.animateTo` al fondo.

- [ ] **Step 8: Insights + Settings**
  - `InsightsScreen`: muestra `insightsProvider` (generado de `budgetSummary`); cada cápsula con title+body; disclaimer visible.
  - `SettingsScreen`: selector de tono (`CupertinoSegmentedControl` strict/neutral/friendly → `settingsDao.setMentorTone`), editor de presupuestos (categoría + límite → `budgetsDao.upsert(..., period actual)`), estado del modelo LLM (descargado / progreso de descarga con `LlamaService.ensureModelDownloaded`), botón "Download model" + "Download voice model".

- [ ] **Step 9: Router + main**
  - `router.dart`: `GoRouter(routes: [GoRoute(path: '/', builder: ShellRoute con NavigationBar de 4 tabs...)])` — estilo Cupertino.
  - `main.dart`: `ProviderScope(child: MoneyLockApp())`; `MoneyLockApp` = `MaterialApp.router(theme: CupertinoThemeData, routerConfig: router)`; `WidgetsFlutterBinding.ensureInitialized()` + `notifications.init()` + deep link handler (Task 5).

- [ ] **Step 10: Lint + tests + commit**
  Run: `cd app && flutter analyze` → sin errores.
  Run: `cd app && flutter test` → todos en verde.
  ```bash
  git add app/lib
  git commit -m "feat: dashboard, chat, insights, settings y navegacion"
  ```

---

### Task 7: Backend de sync (FastAPI + SQLite + Alembic)

**Files:**
- Create: `backend/app/main.py`, `backend/app/models.py`, `backend/app/schemas.py`, `backend/app/db.py`, `backend/app/security.py`, `backend/app/routers/sync.py`, `backend/app/routers/users.py`
- Create: `backend/alembic.ini`, `backend/alembic/env.py`, `backend/alembic/versions/0001_initial.py`
- Create: `backend/requirements.txt`, `backend/pyproject.toml`, `backend/tests/test_sync.py`, `backend/.env.example`
- Create: `app/lib/sync/api_client.dart`

**Interfaces:**
- Consumes: nada de la app (el cliente sync es nuevo).
- Produces (API):
  - `POST /users` body `{email}` → `{id, api_key}` (uuid4 hex).
  - `POST /sync/transactions` header `X-API-Key`, body `{transactions: [{amount, currency, merchant, category, source, raw_text, timestamp, dedup_hash}]}` → `{inserted: n, duplicates: m}`. Upsert por `dedup_hash` (unique por user).
  - `GET /sync/transactions?since=<iso>` → `{transactions: [...]}`.
  - `GET /health` → `{status: "ok"}`.
  - `app/lib/sync/api_client.dart`: `class SyncClient { SyncClient(this.baseUrl, this.apiKey); Future<SyncStats> push(List<LocalTx> txs); Future<List<LocalTx>> pull(DateTime since); }` con reintento simple (2 retries, backoff 1s/3s) y sin bloqueo (fire-and-forget desde UI).

- [ ] **Step 1: Setup del backend**
  ```bash
  mkdir -p backend/app/routers backend/tests backend/alembic/versions
  cd backend && python3 -m venv .venv && source .venv/bin/activate
  pip install fastapi "uvicorn[standard]" sqlalchemy alembic pydantic pytest httpx python-dotenv
  pip freeze > requirements.txt
  ```

- [ ] **Step 2: Test que falla del sync**

`backend/tests/test_sync.py`:
```python
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.db import Base, engine

@pytest.fixture(autouse=True)
def _reset_db():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    yield

def _client() -> TestClient:
    return TestClient(app)

def test_health():
    assert _client().get("/health").json() == {"status": "ok"}

def test_create_user_and_sync_roundtrip():
    c = _client()
    user = c.post("/users", json={"email": "a@b.co"}).json()
    api_key = user["api_key"]
    headers = {"X-API-Key": api_key}
    tx = {"amount": 12.5, "currency": "USD", "merchant": "Starbucks",
          "category": "Coffee & Dining", "source": "shortcut",
          "raw_text": "Starbucks $12.50", "timestamp": "2026-08-13T10:00:00",
          "dedup_hash": "abc123"}
    r = c.post("/sync/transactions", headers=headers,
               json={"transactions": [tx]})
    assert r.status_code == 200
    assert r.json() == {"inserted": 1, "duplicates": 0}
    r2 = c.post("/sync/transactions", headers=headers,
                json={"transactions": [tx]})
    assert r2.json() == {"inserted": 0, "duplicates": 1}
    pulled = c.get("/sync/transactions?since=2026-01-01T00:00:00",
                   headers=headers).json()
    assert len(pulled["transactions"]) == 1

def test_sync_requires_api_key():
    r = _client().post("/sync/transactions", json={"transactions": []})
    assert r.status_code == 401
```

- [ ] **Step 3: Run test para verificar que falla**
  Run: `cd backend && source .venv/bin/activate && pytest tests/test_sync.py -v`
  Expected: FAIL — app.main no existe.

- [ ] **Step 4: Implementar backend**

`backend/app/db.py`:
```python
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

DATABASE_URL = "sqlite:///./moneylock.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine, autoflush=False)

class Base(DeclarativeBase):
    pass
```

`backend/app/models.py`:
```python
from datetime import datetime
from sqlalchemy import String, Float, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from .db import Base

class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True)
    api_key: Mapped[str] = mapped_column(String(64), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

class Transaction(Base):
    __tablename__ = "transactions"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    amount: Mapped[float] = mapped_column(Float)
    currency: Mapped[str] = mapped_column(String(3), default="USD")
    merchant: Mapped[str] = mapped_column(String(255), default="")
    category: Mapped[str] = mapped_column(String(80), default="Other")
    source: Mapped[str] = mapped_column(String(20))
    raw_text: Mapped[str] = mapped_column(String(2000))
    timestamp: Mapped[datetime] = mapped_column(DateTime)
    dedup_hash: Mapped[str] = mapped_column(String(64))
    __table_args__ = (__import__("sqlalchemy").UniqueConstraint("user_id", "dedup_hash", name="uq_user_dedup"),)
```

`backend/app/security.py`:
```python
import secrets
from fastapi import Header, HTTPException
from sqlalchemy.orm import Session
from .models import User

def new_api_key() -> str:
    return secrets.token_hex(32)

def require_user(api_key: str = Header(alias="X-API-Key"), db: Session = None):
    if not api_key:
        raise HTTPException(status_code=401, detail="Missing API key")
    user = db.query(User).filter(User.api_key == api_key).first()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return user
```
(Nota: inyectar `db` via `Depends(get_db)` en el router; patrón estándar FastAPI.)

`backend/app/schemas.py`:
```python
from datetime import datetime
from pydantic import BaseModel, Field

class UserCreate(BaseModel):
    email: str = Field(min_length=3, max_length=255)

class UserOut(BaseModel):
    id: str
    api_key: str

class SyncTransaction(BaseModel):
    amount: float = Field(gt=0)
    currency: str = Field(default="USD", pattern="^(USD|CAD)$")
    merchant: str = Field(default="", max_length=255)
    category: str = Field(default="Other", max_length=80)
    source: str = Field(pattern="^(shortcut|voice|manual)$")
    raw_text: str = Field(max_length=2000)
    timestamp: datetime
    dedup_hash: str = Field(min_length=8, max_length=64)

class SyncRequest(BaseModel):
    transactions: list[SyncTransaction]

class SyncResult(BaseModel):
    inserted: int
    duplicates: int
```

`backend/app/routers/users.py`:
```python
import uuid
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..db import SessionLocal
from ..models import User
from ..schemas import UserCreate, UserOut
from ..security import new_api_key

router = APIRouter()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@router.post("", response_model=UserOut)
def create_user(body: UserCreate, db: Session = Depends(get_db)):
    user = User(id=str(uuid.uuid4()), email=body.email, api_key=new_api_key())
    db.add(user)
    db.commit()
    return UserOut(id=user.id, api_key=user.api_key)
```

`backend/app/routers/sync.py`:
```python
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.orm import Session
from ..db import SessionLocal
from ..models import User, Transaction
from ..schemas import SyncRequest, SyncResult, SyncTransaction

router = APIRouter()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def _user(db: Session, api_key: str | None) -> User:
    if not api_key:
        raise HTTPException(status_code=401, detail="Missing API key")
    user = db.query(User).filter(User.api_key == api_key).first()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return user

@router.post("", response_model=SyncResult)
def push(body: SyncRequest, api_key: str | None = Header(default=None, alias="X-API-Key"),
         db: Session = Depends(get_db)):
    user = _user(db, api_key)
    inserted = duplicates = 0
    for tx in body.transactions:
        exists = db.query(Transaction).filter(
            Transaction.user_id == user.id,
            Transaction.dedup_hash == tx.dedup_hash).first()
        if exists:
            duplicates += 1
            continue
        db.add(Transaction(user_id=user.id, amount=tx.amount,
            currency=tx.currency, merchant=tx.merchant, category=tx.category,
            source=tx.source, raw_text=tx.raw_text, timestamp=tx.timestamp,
            dedup_hash=tx.dedup_hash))
        inserted += 1
    db.commit()
    return SyncResult(inserted=inserted, duplicates=duplicates)

@router.get("")
def pull(since: datetime | None = None,
         api_key: str | None = Header(default=None, alias="X-API-Key"),
         db: Session = Depends(get_db)):
    user = _user(db, api_key)
    q = db.query(Transaction).filter(Transaction.user_id == user.id)
    if since:
        q = q.filter(Transaction.timestamp >= since)
    rows = q.order_by(Transaction.timestamp.desc()).all()
    return {"transactions": [{
        "amount": r.amount, "currency": r.currency, "merchant": r.merchant,
        "category": r.category, "source": r.source, "raw_text": r.raw_text,
        "timestamp": r.timestamp.isoformat(), "dedup_hash": r.dedup_hash,
    } for r in rows]}
```

`backend/app/main.py`:
```python
from fastapi import FastAPI
from .routers import users, sync
from .db import Base, engine

Base.metadata.create_all(engine)

app = FastAPI(title="Moneylock Sync")
app.include_router(users.router, prefix="/users", tags=["users"])
app.include_router(sync.router, prefix="/sync/transactions", tags=["sync"])

@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 5: Alembic inicial**
  `backend/alembic.ini` + `alembic/env.py` con `target_metadata = Base.metadata` y `sqlalchemy.url = sqlite:///./moneylock.db`.
  Run: `cd backend && source .venv/bin/activate && alembic init alembic` (si no se escribieron a mano) y luego:
  Run: `cd backend && alembic revision --autogenerate -m "initial schema" && alembic upgrade head`
  Expected: migración `versions/0001_initial.py` generada y aplicada sin error.

- [ ] **Step 6: Run tests**
  Run: `cd backend && source .venv/bin/activate && pytest tests/test_sync.py -v`
  Expected: PASS (3 tests).

- [ ] **Step 7: Cliente Dart de sync**

`app/lib/sync/api_client.dart`:
```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SyncStats { final int inserted; final int duplicates; SyncStats(this.inserted, this.duplicates); }

class SyncClient {
  final String baseUrl;
  final String apiKey;
  SyncClient(this.baseUrl, this.apiKey);

  Future<SyncStats> push(List<Map<String, dynamic>> txs) =>
      _withRetry(() async {
        final r = await http.post(Uri.parse('$baseUrl/sync/transactions'),
            headers: {'Content-Type': 'application/json', 'X-API-Key': apiKey},
            body: jsonEncode({'transactions': txs}));
        if (r.statusCode != 200) throw Exception('sync push ${r.statusCode}');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return SyncStats(j['inserted'] as int, j['duplicates'] as int);
      });

  Future<List<Map<String, dynamic>>> pull(DateTime since) =>
      _withRetry(() async {
        final r = await http.get(
            Uri.parse('$baseUrl/sync/transactions?since=${since.toUtc().toIso8601String()}'),
            headers: {'X-API-Key': apiKey});
        if (r.statusCode != 200) throw Exception('sync pull ${r.statusCode}');
        return (jsonDecode(r.body)['transactions'] as List).cast<Map<String, dynamic>>();
      });

  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try { return await fn(); } catch (_) {
        if (attempt == 2) rethrow;
        await Future.delayed(Duration(seconds: attempt == 0 ? 1 : 3));
      }
    }
    throw StateError('unreachable');
  }
}
```
SettingsScreen añade: campos baseUrl + apiKey (guardados en `settings` table con keys `sync_base_url`, `sync_api_key`) y botón "Sync now" que hace `push` de transacciones locales sin `synced_at` (fuera de alcance: columna `synced_at` — se sincroniza todo cada vez; aceptable para v1 de respaldo).

- [ ] **Step 8: Lint + tests + commit**
  Run: `cd app && flutter analyze` → sin errores.
  Run: `cd backend && source .venv/bin/activate && pytest -q`
  ```bash
  git add backend app/lib/sync
  git commit -m "feat: backend de sync (FastAPI + SQLite + Alembic) y cliente dart"
  ```

---

### Task 8: Polishing final, README y verificación integral

**Files:**
- Create: `README.md` (raíz del repo)
- Modify: `app/lib/main.dart` (verificación de integración)

- [ ] **Step 1: README**
  - Qué es Moneylock, arquitectura (diagrama ASCII del spec), requisitos (Flutter, Xcode, Homebrew), cómo correr la app (`cd app && flutter run`), cómo correr el backend (`cd backend && source .venv/bin/activate && uvicorn app.main:app`), cómo configurar el Apple Shortcut (referencia a `docs/apple-shortcut.md`), licencias de modelos (Qwen Apache 2.0, whisper MIT).

- [ ] **Step 2: Verificación integral**
  Run: `cd app && flutter analyze` → sin errores.
  Run: `cd app && flutter test` → todos en verde.
  Run: `cd backend && source .venv/bin/activate && pytest -q` → en verde.
  Run: `git status` → limpio tras commits.

- [ ] **Step 3: Smoke test en simulador (manual)**
  Run: `cd app && flutter run -d "iPhone"` (primer simulador disponible)
  Verificar: dashboard abre; descarga de modelo con progreso en Settings; add manual persiste transacción; chat envía y recibe respuesta del mentor (o fallback si el modelo tarda); insights muestran cápsulas con disclaimer. Reportar en el commit final cualquier ajuste requerido.

- [ ] **Step 4: Commit final**
  ```bash
  git add README.md
  git commit -m "docs: README con arquitectura, setup e instrucciones"
  ```

---


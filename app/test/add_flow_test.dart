import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/core/notifications.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/add/add_transaction_flow.dart';
import 'package:moneylock/llm/categorizer_agent.dart';
import 'package:moneylock/llm/llm_provider.dart';
import 'package:moneylock/llm/mentor_agent.dart';

class _FakeLlm implements LlmProvider {
  final String response;
  _FakeLlm(this.response);
  @override
  Future<String> complete(String system, String user,
      {double temperature = 0.2}) async => response;
}

class _FakeNotifications extends LocalNotifications {
  final shown = <({String title, String body, Severity severity})>[];
  @override
  Future<void> init() async {}
  @override
  Future<void> show(String title, String body, Severity severity) async {
    shown.add((title: title, body: body, severity: severity));
  }
}

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('inserta, persiste mensaje del mentor y notifica', () async {
    final db = _db();
    final notif = _FakeNotifications();
    final flow = AddTransactionFlow(
      categorizer: CategorizerAgent(_FakeLlm(
          '{"amount": 45.5, "currency": "USD", "merchant": "Starbucks", "category": "Coffee & Dining", "confidence": 0.9}')),
      mentor: MentorAgent(_FakeLlm('irrelevant'), db),
      db: db,
      notifications: notif,
    );

    final r = await flow.run(rawText: 'Starbucks 45.50 USD', source: 'shortcut');

    expect(r.inserted, isTrue);
    expect(r.error, isNull);
    expect(r.verdict, isNotNull);
    expect(r.verdict!.severity, Severity.info);
    final txs = await db.transactionsDao.recent(10);
    expect(txs, hasLength(1));
    expect(txs.single.merchant, 'Starbucks');
    expect(txs.single.source, 'shortcut');
    expect(notif.shown, hasLength(1));
    expect(notif.shown.single.title, 'Transaction recorded');
    expect(await db.messagesDao.watchAll().first, hasLength(1));
    await db.close();
  });

  test('fallback determinista cuando el LLM devuelve basura', () async {
    final db = _db();
    final notif = _FakeNotifications();
    final flow = AddTransactionFlow(
      categorizer: CategorizerAgent(_FakeLlm('I cannot parse that.')),
      mentor: MentorAgent(_FakeLlm('irrelevant'), db),
      db: db,
      notifications: notif,
    );

    final r = await flow.run(rawText: 'starbucks 12.50', source: 'voice');

    expect(r.inserted, isTrue);
    final txs = await db.transactionsDao.recent(10);
    expect(txs.single.amount, closeTo(12.5, 0.001));
    expect(txs.single.category, 'Coffee & Dining');
    await db.close();
  });

  test('duplicado no inserta ni notifica', () async {
    final db = _db();
    final notif = _FakeNotifications();
    final flow = AddTransactionFlow(
      categorizer: CategorizerAgent(_FakeLlm(
          '{"amount": 45.5, "currency": "USD", "merchant": "Starbucks", "category": "Coffee & Dining", "confidence": 0.9}')),
      mentor: MentorAgent(_FakeLlm('irrelevant'), db),
      db: db,
      notifications: notif,
    );
    final ts = DateTime(2026, 8, 13, 12);

    final first = await flow.run(
        rawText: 'Starbucks 45.50 USD', source: 'shortcut', timestamp: ts);
    final second = await flow.run(
        rawText: 'Starbucks 45.50 USD', source: 'shortcut', timestamp: ts);

    expect(first.inserted, isTrue);
    expect(second.inserted, isFalse);
    expect(second.error, isNull);
    expect(await db.transactionsDao.recent(10), hasLength(1));
    expect(notif.shown, hasLength(1));
    expect(await db.messagesDao.watchAll().first, hasLength(1));
    await db.close();
  });

  test('sin amount extraible devuelve error sin insertar', () async {
    final db = _db();
    final notif = _FakeNotifications();
    final flow = AddTransactionFlow(
      categorizer: CategorizerAgent(_FakeLlm('garbage')), // fallback tampoco
      mentor: MentorAgent(_FakeLlm('irrelevant'), db),
      db: db,
      notifications: notif,
    );

    final r = await flow.run(rawText: 'unknown purchase', source: 'manual');

    expect(r.inserted, isFalse);
    expect(r.error, 'Could not extract amount');
    expect(await db.transactionsDao.recent(10), isEmpty);
    expect(notif.shown, isEmpty);
    await db.close();
  });
}
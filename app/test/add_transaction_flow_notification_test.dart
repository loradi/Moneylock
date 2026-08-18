import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/core/notification_scheduler.dart';
import 'package:moneylock/core/notifications.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/add/add_transaction_flow.dart';
import 'package:moneylock/llm/categorizer_agent.dart';
import 'package:moneylock/llm/llm_provider.dart';
import 'package:moneylock/llm/mentor_agent.dart' show Severity, MentorAgent;

class _FakeLlm implements LlmProvider {
  @override
  Future<String> complete(String system, String user, {double? temperature}) async =>
      '{"amount": 12.0, "merchant": "Test", "category": "Other", "currency": "USD"}';
}

class _FakeNotifications implements NotificationScheduling {
  int refreshTriggeringCancelCalls = 0;
  @override
  Future<void> scheduleAt(int id, DateTime when, String title, String body) async {}
  @override
  Future<void> cancel(int id) async => refreshTriggeringCancelCalls++;
}

class _ThrowingNotifications implements NotificationScheduling {
  @override
  Future<void> scheduleAt(int id, DateTime when, String title, String body) async {
    throw Exception('scheduling failed');
  }
  @override
  Future<void> cancel(int id) async {
    throw Exception('cancel failed');
  }
}

class _NoOpNotifications implements NotificationScheduling {
  @override
  Future<void> scheduleAt(int id, DateTime when, String title, String body) async {}
  @override
  Future<void> cancel(int id) async {}
}

// A fake implementation of LocalNotifications that doesn't require Flutter initialization
class _FakeLocalNotifications extends LocalNotifications {
  @override
  Future<void> show(String title, String body, Severity severity) async {
    // no-op for testing
  }
}

// A LocalNotifications whose show() always fails, to exercise the guard
// around the post-insert mentor/message-log/notification block.
class _ThrowingLocalNotifications extends LocalNotifications {
  @override
  Future<void> show(String title, String body, Severity severity) async {
    throw Exception('notification failed');
  }
}

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('a successfully recorded transaction triggers a scheduler refresh', () async {
    final db = _db();
    final llm = _FakeLlm();
    final fakeNotifications = _FakeNotifications();
    final flow = AddTransactionFlow(
      categorizer: CategorizerAgent(llm),
      mentor: MentorAgent(llm, db),
      db: db,
      notifications: _FakeLocalNotifications(),
      scheduler: NotificationScheduler(db, fakeNotifications),
    );

    final result = await flow.run(rawText: 'Test 12 USD', source: 'manual');

    // refresh() always cancels the 4 known IDs first; a non-zero count
    // proves refresh() ran as a result of this call.
    expect(fakeNotifications.refreshTriggeringCancelCalls, greaterThan(0));
    expect(result.inserted, isTrue);
    await db.close();
  });

  test('a scheduler failure does not mask a successful transaction', () async {
    final db = _db();
    final llm = _FakeLlm();
    final flow = AddTransactionFlow(
      categorizer: CategorizerAgent(llm),
      mentor: MentorAgent(llm, db),
      db: db,
      notifications: _FakeLocalNotifications(),
      scheduler: NotificationScheduler(db, _ThrowingNotifications(), now: () => DateTime(2024, 1, 1, 10, 0)),
    );

    final result = await flow.run(rawText: 'Test 12 USD', source: 'manual');

    expect(result.inserted, isTrue);
    await db.close();
  });

  test('a mentor/notification failure does not mask a successful transaction', () async {
    final db = _db();
    final llm = _FakeLlm();
    final flow = AddTransactionFlow(
      categorizer: CategorizerAgent(llm),
      mentor: MentorAgent(llm, db),
      db: db,
      notifications: _ThrowingLocalNotifications(),
      scheduler: NotificationScheduler(db, _NoOpNotifications()),
    );

    final result = await flow.run(rawText: 'Test 12 USD', source: 'manual');

    expect(result.inserted, isTrue);
    await db.close();
  });
}

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/core/notification_scheduler.dart';
import 'package:moneylock/core/notifications.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/add/add_transaction_flow.dart';
import 'package:moneylock/llm/categorizer_agent.dart';
import 'package:moneylock/llm/llm_provider.dart';
import 'package:moneylock/llm/mentor_agent.dart';

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
      notifications: LocalNotifications(),
      scheduler: NotificationScheduler(db, fakeNotifications),
    );

    await flow.run(rawText: 'Test 12 USD', source: 'manual');

    // refresh() always cancels the 4 known IDs first; a non-zero count
    // proves refresh() ran as a result of this call.
    expect(fakeNotifications.refreshTriggeringCancelCalls, greaterThan(0));
    await db.close();
  });
}

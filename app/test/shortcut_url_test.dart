import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/core/deep_links.dart';
import 'package:moneylock/core/notification_scheduler.dart';
import 'package:moneylock/core/notifications.dart';
import 'package:moneylock/features/add/add_transaction_flow.dart';
import 'package:moneylock/llm/categorizer_agent.dart';
import 'package:moneylock/llm/llm_provider.dart';
import 'package:moneylock/llm/mentor_agent.dart';

import 'helpers/test_database.dart';

class _FakeLlm implements LlmProvider {
  @override
  Future<String> complete(
    String system,
    String user, {
    double temperature = 0.2,
  }) async =>
      '{"amount": 12.34, "currency": "USD", "merchant": "ColdLinkCafe", "category": "Coffee & Dining", "confidence": 0.9}';
}

class _FakeNotifications extends LocalNotifications {
  @override
  Future<void> show(String title, String body, Severity severity) async {}
}

class _FakeScheduling implements NotificationScheduling {
  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> scheduleAt(
    int id,
    DateTime when,
    String title,
    String body,
  ) async {}
}

void main() {
  test('parsea URL del shortcut', () {
    final u = Uri.parse('moneylock://add?amount=45.50&merchant=Starbucks');
    expect(parseShortcutUrl(u), 'Starbucks 45.50 USD');
  });
  test('sin amount lanza FormatException', () {
    expect(
      () => parseShortcutUrl(Uri.parse('moneylock://add?merchant=X')),
      throwsFormatException,
    );
  });

  test(
    'entregas simultaneas del mismo deep link insertan una sola vez',
    () async {
      final db = createTestDatabase();
      final llm = _FakeLlm();
      final handler = DeepLinkHandler(
        flow: AddTransactionFlow(
          categorizer: CategorizerAgent(llm),
          mentor: MentorAgent(llm, db),
          db: db,
          notifications: _FakeNotifications(),
          scheduler: NotificationScheduler(db, _FakeScheduling()),
        ),
      );
      final uri = Uri.parse(
        'moneylock://add?amount=12.34&merchant=ColdLinkCafe',
      );

      await Future.wait([handler.handle(uri), handler.handle(uri)]);

      expect(await db.transactionsDao.recent(10), hasLength(1));
      await db.close();
    },
  );

  test('initial link repetido por el stream se procesa una sola vez', () async {
    final db = createTestDatabase();
    final llm = _FakeLlm();
    final handler = DeepLinkHandler(
      flow: AddTransactionFlow(
        categorizer: CategorizerAgent(llm),
        mentor: MentorAgent(llm, db),
        db: db,
        notifications: _FakeNotifications(),
        scheduler: NotificationScheduler(db, _FakeScheduling()),
      ),
    );
    final uri = Uri.parse('moneylock://add?amount=12.34&merchant=ColdLinkCafe');
    final links = StreamController<Uri>();

    await handler.startListening(
      getInitialLink: () async => uri,
      uriLinkStream: links.stream,
    );
    links.add(uri);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await db.transactionsDao.recent(10), hasLength(1));
    await links.close();
    await db.close();
  });
}

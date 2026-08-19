import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/subscription_summary.dart';
import 'package:moneylock/data/transaction_summary.dart';
import 'package:moneylock/features/chat/chat_screen.dart';
import 'package:moneylock/providers.dart';
import 'package:moneylock/widgets/subscription_row.dart';
import 'package:moneylock/widgets/transaction_row.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

MentorMessage _msg({
  required int id,
  required String kind,
  required String content,
  String? dataJson,
}) =>
    MentorMessage(
      id: id,
      role: 'mentor',
      content: content,
      createdAt: DateTime.now(),
      severity: 'info',
      kind: kind,
      dataJson: dataJson,
    );

void main() {
  testWidgets('renders an empty chat with no exception', (tester) async {
    final db = _db();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messagesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VECTOR'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders a transaction_list bubble with cards and no Delete/Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'transaction_list',
      content: 'Found 1 matching "Nike", totaling \$50.00.',
      dataJson: encodeTransactionSummaries([
        TransactionSummary(
          id: 1,
          merchant: 'Nike Store',
          amount: 50.0,
          category: 'Shopping & E-commerce',
          timestamp: DateTime(2026, 8, 1),
        ),
      ]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messagesStreamProvider.overrideWith((ref) => Stream.value([message])),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TransactionRow), findsOneWidget);
    expect(find.text('Nike Store'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders a delete_confirm bubble with Delete and Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'delete_confirm',
      content: 'Found this transaction -- want me to delete it?',
      dataJson: encodeTransactionSummaries([
        TransactionSummary(
          id: 1,
          merchant: 'Nike Store',
          amount: 89.99,
          category: 'Shopping & E-commerce',
          timestamp: DateTime(2026, 8, 1),
        ),
      ]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messagesStreamProvider.overrideWith((ref) => Stream.value([message])),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TransactionRow), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders a subscription_list bubble with cards and no Cancel-subscription button',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'subscription_list',
      content: 'Found 1 subscription, ~\$15.99/month.',
      dataJson: encodeSubscriptionSummaries([
        SubscriptionSummary(
          id: 1,
          name: 'Netflix',
          brandKey: 'netflix',
          amount: 15.99,
          currency: 'USD',
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 1),
        ),
      ]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messagesStreamProvider.overrideWith((ref) => Stream.value([message])),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SubscriptionRow), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Cancel Subscription'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders a cancel_confirm bubble with Cancel Subscription and Keep It buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'cancel_confirm',
      content: 'Found this subscription -- want me to cancel it?',
      dataJson: encodeSubscriptionSummaries([
        SubscriptionSummary(
          id: 1,
          name: 'Netflix',
          brandKey: 'netflix',
          amount: 15.99,
          currency: 'USD',
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 1),
        ),
      ]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messagesStreamProvider.overrideWith((ref) => Stream.value([message])),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SubscriptionRow), findsOneWidget);
    expect(find.text('Cancel Subscription'), findsOneWidget);
    expect(find.text('Keep It'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/budget_change_summary.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/new_subscription_summary.dart';
import 'package:moneylock/data/subscription_edit_summary.dart';
import 'package:moneylock/data/subscription_summary.dart';
import 'package:moneylock/data/transaction_edit_summary.dart';
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

  testWidgets('renders a budget_confirm bubble with Confirm and Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'budget_confirm',
      content: 'Change your Groceries limit from \$300.00 to \$400.00?',
      dataJson: encodeBudgetChangeSummary(const BudgetChangeSummary(
        category: 'Groceries',
        currentLimit: 300.0,
        proposedLimit: 400.0,
        period: '2026-08',
      )),
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

    expect(find.textContaining('Groceries limit'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders an add_subscription_confirm bubble with Confirm and Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'add_subscription_confirm',
      content: 'Add Netflix at \$30.00/month, starting Sep 20?',
      dataJson: encodeNewSubscriptionSummary(NewSubscriptionSummary(
        name: 'Netflix',
        amount: 30.0,
        nextChargeDate: DateTime(2026, 9, 20),
      )),
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

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders an edit_transaction_confirm bubble with Confirm and Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'edit_transaction_confirm',
      content: "Change this transaction's amount from \$45.00 to \$50.00?",
      dataJson: encodeTransactionEditSummary(TransactionEditSummary(
        transaction: TransactionSummary(
          id: 1,
          merchant: 'Nike Store',
          amount: 45.0,
          category: 'Shopping & E-commerce',
          timestamp: DateTime(2026, 8, 1),
        ),
        newAmount: 50.0,
      )),
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

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });

  testWidgets('renders an edit_subscription_confirm bubble with Confirm and Cancel buttons',
      (tester) async {
    final db = _db();
    final message = _msg(
      id: 1,
      kind: 'edit_subscription_confirm',
      content: 'Change Netflix from \$15.99 to \$18.99?',
      dataJson: encodeSubscriptionEditSummary(SubscriptionEditSummary(
        subscription: SubscriptionSummary(
          id: 1,
          name: 'Netflix',
          brandKey: 'netflix',
          amount: 15.99,
          currency: 'USD',
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 1),
        ),
        newAmount: 18.99,
      )),
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

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}

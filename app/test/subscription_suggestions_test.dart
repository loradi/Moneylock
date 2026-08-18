import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';
import 'package:moneylock/features/subscriptions/subscription_suggestions.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
  });

  tearDown(() => db.close());

  Future<Transaction> insertTx(String merchant, double amount, DateTime timestamp) async {
    final outcome = await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: amount,
      currency: 'USD',
      merchant: merchant,
      category: 'Entertainment',
      source: 'manual',
      rawText: '$merchant $amount',
      timestamp: timestamp,
    ));
    return outcome.transaction!;
  }

  test('same merchant 2+ times within 10% amount band is suggested', () async {
    final txs = [
      await insertTx('Netflix', 15.99, DateTime(2026, 7, 1)),
      await insertTx('Netflix', 15.99, DateTime(2026, 8, 1)),
    ];

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: const [],
      dismissedMerchants: const {},
    );

    expect(suggestions, hasLength(1));
    expect(suggestions.single.merchant, 'Netflix');
    expect(suggestions.single.occurrenceCount, 2);
  });

  test('a single occurrence is not suggested', () async {
    final txs = [await insertTx('Netflix', 15.99, DateTime(2026, 7, 1))];

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: const [],
      dismissedMerchants: const {},
    );

    expect(suggestions, isEmpty);
  });

  test('amounts more than 10% apart are not suggested', () async {
    final txs = [
      await insertTx('Uber', 8.00, DateTime(2026, 7, 1)),
      await insertTx('Uber', 40.00, DateTime(2026, 8, 1)),
    ];

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: const [],
      dismissedMerchants: const {},
    );

    expect(suggestions, isEmpty);
  });

  test('a merchant matching an existing subscription (case-insensitive) is excluded', () async {
    final txs = [
      await insertTx('netflix', 15.99, DateTime(2026, 7, 1)),
      await insertTx('netflix', 15.99, DateTime(2026, 8, 1)),
    ];
    final subId = await db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: 'Netflix',
      amount: 15.99,
      cycle: 'monthly',
      nextChargeDate: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 1, 1),
    ));
    final existing = await db.subscriptionsDao.allForScheduling();

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: existing,
      dismissedMerchants: const {},
    );

    expect(suggestions, isEmpty);
    expect(subId, isNotNull);
  });

  test('a dismissed merchant is excluded', () async {
    final txs = [
      await insertTx('Spotify', 9.99, DateTime(2026, 7, 1)),
      await insertTx('Spotify', 9.99, DateTime(2026, 8, 1)),
    ];

    final suggestions = detectSuggestions(
      transactions: txs,
      existingSubscriptions: const [],
      dismissedMerchants: {'spotify'},
    );

    expect(suggestions, isEmpty);
  });
}

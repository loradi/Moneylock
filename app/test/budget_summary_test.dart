import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';
import 'package:moneylock/features/insights/insights_agent.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('budgetSummaryProvider solo suma transacciones del periodo actual',
      () async {
    final db = _db();
    final now = DateTime.now();
    final old = now.subtract(const Duration(days: 40));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 100.0,
      currency: 'USD',
      merchant: 'Starbucks',
      category: 'Coffee & Dining',
      source: 'manual',
      rawText: 'current month tx',
      timestamp: now,
    ));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 999.0,
      currency: 'USD',
      merchant: 'Old Store',
      category: 'Other',
      source: 'manual',
      rawText: 'previous month tx',
      timestamp: old,
    ));

    final period = _currentPeriod();
    await db.budgetsDao.upsert('Coffee & Dining', 500.0, period);
    await db.budgetsDao.upsert('Other', 1.0, '1999-01');

    final container =
        ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    final completed = Completer<BudgetSummary>();
    final sub = container.listen<AsyncValue<BudgetSummary>>(
        budgetSummaryProvider, (prev, next) {
      final v = next.value;
      if (v != null && v.totalLimit > 0 && !completed.isCompleted) {
        completed.complete(v);
      }
    });
    addTearDown(sub.close);
    final summary = await completed.future;

    expect(summary.totalSpent, closeTo(100.0, 0.001));
    expect(summary.byCategory['Other'], isNull);
    expect(summary.byCategory['Coffee & Dining'], closeTo(100.0, 0.001));
    expect(summary.totalLimit, closeTo(500.0, 0.001));
    expect(summary.byCategoryLimits['Other'], isNull);
  });
}

String _currentPeriod() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
}
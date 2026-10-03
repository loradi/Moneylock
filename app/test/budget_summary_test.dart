import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/exchange_rate_service.dart';
import 'package:moneylock/data/transactions_dao.dart';
import 'package:moneylock/features/budget/plan_period.dart';
import 'package:moneylock/features/insights/insights_agent.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
  driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
);

class _FakeExchangeRateService extends ExchangeRateService {
  @override
  Future<ExchangeRateQuote> quote({
    required String base,
    required String target,
    DateTime? date,
  }) async => ExchangeRateQuote(
    base: base,
    quote: target,
    rate: base == target ? 1 : 1.5,
    asOf: date ?? DateTime(2026, 1, 1),
  );
}

final _exchangeRates = _FakeExchangeRateService();

void main() {
  test(
    'budgetSummaryProvider solo suma transacciones del periodo actual',
    () async {
      final db = _db();
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 40));
      await db.transactionsDao.insertWithDedup(
        NewTransaction(
          amount: 100.0,
          currency: 'USD',
          merchant: 'Starbucks',
          category: 'Coffee & Dining',
          source: 'manual',
          rawText: 'current month tx',
          timestamp: now,
        ),
      );
      await db.transactionsDao.insertWithDedup(
        NewTransaction(
          amount: 999.0,
          currency: 'USD',
          merchant: 'Old Store',
          category: 'Other',
          source: 'manual',
          rawText: 'previous month tx',
          timestamp: old,
        ),
      );
      await db.transactionsDao.insertWithDedup(
        NewTransaction(
          amount: 55.0,
          currency: 'EUR',
          merchant: 'Foreign Store',
          category: 'Shopping & E-commerce',
          source: 'manual',
          rawText: 'current month EUR tx',
          timestamp: now,
        ),
      );

      final period = _currentPeriod();
      await db.budgetsDao.upsert('Coffee & Dining', 500.0, period);
      await db.budgetsDao.upsert('Other', 1.0, '1999-01');

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          exchangeRateServiceProvider.overrideWithValue(_exchangeRates),
        ],
      );
      addTearDown(container.dispose);
      final completed = Completer<BudgetSummary>();
      final sub = container.listen<AsyncValue<BudgetSummary>>(
        budgetSummaryProvider,
        (prev, next) {
          final v = next.value;
          if (v != null && v.totalLimit > 0 && !completed.isCompleted) {
            completed.complete(v);
          }
        },
      );
      addTearDown(sub.close);
      final summary = await completed.future;

      expect(summary.totalSpent, closeTo(182.5, 0.001));
      expect(summary.byCategory['Other'], isNull);
      expect(summary.byCategory['Coffee & Dining'], closeTo(100.0, 0.001));
      expect(summary.byCategoryAllCurrencies['Shopping & E-commerce'], {
        'USD': 82.5,
      });
      expect(summary.totalLimit, closeTo(500.0, 0.001));
      expect(summary.byCategoryLimits['Other'], isNull);
      expect(summary.unconvertedTotals, isEmpty);
    },
  );

  test('budgetSummaryProvider uses the active weekly plan period', () async {
    final db = _db();
    final now = DateTime.now();
    final cycle = PlanCycle.weekly;
    final period = cycle.keyFor(now);
    await db.settingsDao.setPlanCycle(cycle.storageValue);
    await db.budgetsDao.upsert(
      'Groceries',
      150,
      period,
      cycle: cycle.storageValue,
      cycleDays: cycle.fixedDays,
      currency: 'CAD',
    );
    await db.transactionsDao.insertWithDedup(
      NewTransaction(
        amount: 40,
        currency: 'CAD',
        merchant: 'Market',
        category: 'Groceries',
        source: 'manual',
        rawText: 'Market 40',
        timestamp: now,
      ),
    );

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        exchangeRateServiceProvider.overrideWithValue(_exchangeRates),
      ],
    );
    addTearDown(container.dispose);
    final completed = Completer<BudgetSummary>();
    final sub = container.listen<AsyncValue<BudgetSummary>>(
      budgetSummaryProvider,
      (previous, next) {
        final summary = next.value;
        if (summary != null &&
            summary.totalLimit == 150 &&
            !completed.isCompleted) {
          completed.complete(summary);
        }
      },
    );
    addTearDown(sub.close);
    final summary = await completed.future;

    expect(summary.currency, 'CAD');
    expect(summary.totalSpent, 40);
    expect(summary.byCategory['Groceries'], 40);
    expect(summary.cycle, 'weekly');
    expect(summary.periodStart, cycle.startFor(now));
    expect(summary.periodEnd, cycle.endFor(now));
  });

  test('converts the active plan into the global currency', () async {
    final db = _db();
    final now = DateTime.now();
    final period = _currentPeriod();
    await db.settingsDao.setDefaultCurrency('CAD');
    await db.budgetsDao.upsert('Groceries', 250, period, currency: 'USD');
    await db.transactionsDao.insertWithDedup(
      NewTransaction(
        amount: 40,
        currency: 'USD',
        merchant: 'Market',
        category: 'Groceries',
        source: 'manual',
        rawText: 'Market 40',
        timestamp: now,
      ),
    );

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        exchangeRateServiceProvider.overrideWithValue(_exchangeRates),
      ],
    );
    addTearDown(container.dispose);
    final completed = Completer<BudgetSummary>();
    final sub = container.listen<AsyncValue<BudgetSummary>>(
      budgetSummaryProvider,
      (previous, next) {
        final summary = next.value;
        if (summary != null &&
            summary.currency == 'CAD' &&
            summary.totalLimit == 375 &&
            !completed.isCompleted) {
          completed.complete(summary);
        }
      },
    );
    addTearDown(sub.close);
    final summary = await completed.future;

    expect(summary.currency, 'CAD');
    expect(summary.totalSpent, 60);
    expect(summary.totalLimit, 375);
    expect(summary.byCategory['Groceries'], 60);
  });

  test(
    'derives a fortnightly dashboard from the current monthly plan',
    () async {
      final db = _db();
      final now = DateTime.now();
      await db.settingsDao.setPlanCycle('fortnightly');
      await db.budgetsDao.upsert(
        'Groceries',
        300,
        PlanCycle.monthly.keyFor(now),
        currency: 'USD',
      );
      await db.transactionsDao.insertWithDedup(
        NewTransaction(
          amount: 40,
          currency: 'USD',
          merchant: 'Market',
          category: 'Groceries',
          source: 'manual',
          rawText: 'Market 40',
          timestamp: now,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          exchangeRateServiceProvider.overrideWithValue(_exchangeRates),
        ],
      );
      addTearDown(container.dispose);
      final completed = Completer<BudgetSummary>();
      final sub = container.listen<AsyncValue<BudgetSummary>>(
        budgetSummaryProvider,
        (previous, next) {
          final summary = next.value;
          if (summary != null &&
              summary.cycle == 'fortnightly' &&
              summary.totalLimit > 0 &&
              !completed.isCompleted) {
            completed.complete(summary);
          }
        },
      );
      addTearDown(sub.close);
      final summary = await completed.future;

      expect(summary.cycle, 'fortnightly');
      expect(
        summary.totalLimit,
        closeTo(300 * 14 / PlanCycle.monthly.daysFor(now), 0.001),
      );
      expect(summary.byCategory['Groceries'], 40);
    },
  );
}

String _currentPeriod() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
}

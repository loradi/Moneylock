import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('upsert overwrites the limit for the same category and period instead of throwing', () async {
    final db = AppDatabase.forTesting(
      driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
    );
    await db.budgetsDao.upsert('Coffee & Dining', 50.0, '2026-08');
    await db.budgetsDao.upsert('Coffee & Dining', 75.0, '2026-08');
    final rows = await db.budgetsDao.all();
    expect(rows.length, 1);
    expect(rows.first.monthlyLimit, 75.0);
    await db.close();
  });

  test(
    'upsert keeps separate rows for different periods of the same category',
    () async {
      final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
      );
      await db.budgetsDao.upsert('Coffee & Dining', 50.0, '2026-08');
      await db.budgetsDao.upsert('Coffee & Dining', 60.0, '2026-09');
      final rows = await db.budgetsDao.all();
      expect(rows.length, 2);
      await db.close();
    },
  );

  test(
    'copyPeriod copies limits and preserves target-only categories',
    () async {
      final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
      );
      await db.budgetsDao.upsert('Coffee & Dining', 50.0, '2026-08');
      await db.budgetsDao.upsert('Bills & Utilities', 800.0, '2026-08');
      await db.budgetsDao.upsert('Travel', 120.0, '2026-09');

      final copied = await db.budgetsDao.copyPeriod(
        '2026-08',
        '2026-09',
        targetCycleDays: 30,
      );

      expect(copied, 2);
      expect(await db.budgetsDao.limitsForPeriod('2026-09'), {
        'Coffee & Dining': 50.0,
        'Bills & Utilities': 800.0,
        'Travel': 120.0,
      });
      await db.close();
    },
  );

  test('copyPeriod can scale a monthly plan into a weekly plan', () async {
    final db = AppDatabase.forTesting(
      driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
    );
    await db.budgetsDao.upsert(
      'Groceries',
      300.0,
      '2026-09',
      cycle: 'monthly',
      cycleDays: 30,
      currency: 'CAD',
    );

    await db.budgetsDao.copyPeriod(
      '2026-09',
      '2026-09-07',
      targetCycleDays: 7,
      targetCycle: 'weekly',
      targetCurrency: 'CAD',
      multiplier: 7 / 30,
    );

    final copied = (await db.budgetsDao.forPeriod('2026-09-07')).single;
    expect(copied.monthlyLimit, closeTo(70.0, 0.001));
    expect(copied.cycle, 'weekly');
    expect(copied.cycleDays, 7);
    expect(copied.currency, 'CAD');
    await db.close();
  });

  test(
    'convertPeriodCurrency atomically updates caps, income, and plan currency',
    () async {
      final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
      );
      await db.budgetsDao.upsert('Groceries', 100.0, '2026-09');
      await db.budgetsDao.upsert('Transport', 25.555, '2026-09');
      await db.settingsDao.setMonthlyIncome('2026-09', 2000);
      await db.settingsDao.setPlanCurrency('2026-09', 'USD');

      await db.budgetsDao.convertPeriodCurrency(
        '2026-09',
        targetCurrency: 'CAD',
        rate: 1.36,
        income: 2000,
      );

      final rows = await db.budgetsDao.forPeriod('2026-09');
      expect(rows.map((row) => row.currency).toSet(), {'CAD'});
      expect(rows.map((row) => row.monthlyLimit), containsAll([136.0, 34.75]));
      expect(await db.settingsDao.monthlyIncome('2026-09'), 2720.0);
      expect(await db.settingsDao.planCurrency('2026-09'), 'CAD');
      await db.close();
    },
  );
}

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
}

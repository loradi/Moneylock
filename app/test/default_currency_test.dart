import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
  driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
);

void main() {
  test('defaultCurrency defaults to USD', () async {
    final db = _db();
    expect(await db.settingsDao.defaultCurrency(), 'USD');
    await db.close();
  });

  test('setDefaultCurrency persists and is read back', () async {
    final db = _db();
    await db.settingsDao.setDefaultCurrency('EUR');

    expect(await db.settingsDao.defaultCurrency(), 'EUR');
    await db.close();
  });

  test('plan currency is stored per planning period', () async {
    final db = _db();
    expect(await db.settingsDao.planCurrency('2026-09'), isNull);

    await db.settingsDao.setPlanCurrency('2026-09', 'CAD');

    expect(await db.settingsDao.planCurrency('2026-09'), 'CAD');
    expect(await db.settingsDao.planCurrency('2026-10'), isNull);
    await db.close();
  });
}

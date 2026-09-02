import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';

void main() {
  test('stores private income independently for each planning month', () async {
    final db = createTestDatabase();

    await db.settingsDao.setMonthlyIncome('2026-09', 4200);
    await db.settingsDao.setMonthlyIncome('2026-10', 3900);

    expect(await db.settingsDao.monthlyIncome('2026-09'), 4200);
    expect(await db.settingsDao.monthlyIncome('2026-10'), 3900);
    expect(await db.settingsDao.monthlyIncome('2026-11'), isNull);

    await db.close();
  });

  test('stores the private sync configuration together', () async {
    final db = createTestDatabase();

    await db.settingsDao.setSyncConfiguration(
      baseUrl: 'https://sync.moneylock.test',
      apiKey: 'key-123',
    );

    expect(await db.settingsDao.syncConfiguration(), (
      baseUrl: 'https://sync.moneylock.test',
      apiKey: 'key-123',
    ));
    await db.close();
  });
}

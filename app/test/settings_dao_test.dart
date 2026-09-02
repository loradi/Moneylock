import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

import 'helpers/test_database.dart';

import 'package:moneylock/data/savings_goal.dart';

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

  test(
    'stores the private sync URL and exposes a legacy API key for migration',
    () async {
      final db = createTestDatabase();

      await db.settingsDao.setSyncConfiguration(
        baseUrl: 'https://sync.moneylock.test',
      );

      expect(await db.settingsDao.syncConfiguration(), (
        baseUrl: 'https://sync.moneylock.test',
        legacyApiKey: '',
      ));
      await db.close();
    },
  );

  test(
    'moves a legacy SQLite sync key to the credential vault callback',
    () async {
      final db = createTestDatabase();
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(key: 'sync_api_key', value: 'legacy-key'),
          );
      var storedSecurely = '';

      await db.settingsDao.migrateLegacySyncApiKey((key) async {
        storedSecurely = key;
      });

      expect(storedSecurely, 'legacy-key');
      expect((await db.settingsDao.syncConfiguration()).legacyApiKey, isEmpty);
      await db.close();
    },
  );

  test('stores and clears a local savings goal', () async {
    final db = createTestDatabase();
    const goal = SavingsGoal(
      name: 'Emergency fund',
      targetAmount: 5000,
      savedAmount: 1200,
      currency: 'CAD',
    );

    await db.settingsDao.setSavingsGoal(goal);
    final stored = await db.settingsDao.savingsGoal();
    expect(stored?.name, goal.name);
    expect(stored?.targetAmount, goal.targetAmount);
    expect(stored?.savedAmount, goal.savedAmount);
    expect(stored?.currency, goal.currency);
    await db.settingsDao.clearSavingsGoal();
    expect(await db.settingsDao.savingsGoal(), isNull);
    await db.close();
  });
}

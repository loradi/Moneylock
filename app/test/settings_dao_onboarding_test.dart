import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
  driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
);

void main() {
  test('completeOnboarding writes only onboarding_completed', () async {
    final db = _db();

    await db.settingsDao.completeOnboarding();

    expect(await db.settingsDao.onboardingCompleted(), true);
    final rows = await db.select(db.settings).get();
    expect(rows.map((r) => r.key), ['onboarding_completed']);
    await db.close();
  });
}

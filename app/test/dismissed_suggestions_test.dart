import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('dismissedSubscriptionSuggestions defaults to empty', () async {
    final db = _db();
    expect(await db.settingsDao.dismissedSubscriptionSuggestions(), isEmpty);
    await db.close();
  });

  test('dismissSubscriptionSuggestion adds a lowercased entry', () async {
    final db = _db();
    await db.settingsDao.dismissSubscriptionSuggestion('Netflix');

    final dismissed = await db.settingsDao.dismissedSubscriptionSuggestions();

    expect(dismissed, {'netflix'});
    await db.close();
  });

  test('dismissing the same merchant twice does not duplicate it', () async {
    final db = _db();
    await db.settingsDao.dismissSubscriptionSuggestion('Spotify');
    await db.settingsDao.dismissSubscriptionSuggestion('Spotify');

    final dismissed = await db.settingsDao.dismissedSubscriptionSuggestions();

    expect(dismissed, {'spotify'});
    await db.close();
  });

  test('dismissing multiple merchants accumulates them', () async {
    final db = _db();
    await db.settingsDao.dismissSubscriptionSuggestion('Netflix');
    await db.settingsDao.dismissSubscriptionSuggestion('Spotify');

    final dismissed = await db.settingsDao.dismissedSubscriptionSuggestions();

    expect(dismissed, {'netflix', 'spotify'});
    await db.close();
  });
}

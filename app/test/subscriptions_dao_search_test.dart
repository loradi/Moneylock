import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

Future<int> _addSub(AppDatabase db, String name, {String cycle = 'monthly', double amount = 10.0}) =>
    db.subscriptionsDao.add(SubscriptionsCompanion.insert(
      name: name,
      amount: amount,
      cycle: cycle,
      nextChargeDate: DateTime(2026, 9, 1),
      createdAt: DateTime.now(),
    ));

void main() {
  test('search matches by name keyword, case-insensitively on substring', () async {
    final db = _db();
    await _addSub(db, 'Netflix');
    await _addSub(db, 'Spotify');

    final results = await db.subscriptionsDao.search(nameKeyword: 'flix');

    expect(results, hasLength(1));
    expect(results.single.name, 'Netflix');
    await db.close();
  });

  test('search with no keyword returns everything up to the limit', () async {
    final db = _db();
    await _addSub(db, 'Netflix');
    await _addSub(db, 'Spotify');

    final results = await db.subscriptionsDao.search();

    expect(results, hasLength(2));
    await db.close();
  });

  test('search with no matches returns an empty list', () async {
    final db = _db();
    await _addSub(db, 'Netflix');

    final results = await db.subscriptionsDao.search(nameKeyword: 'nothing');

    expect(results, isEmpty);
    await db.close();
  });

  test('search respects the limit parameter', () async {
    final db = _db();
    for (var i = 0; i < 5; i++) {
      await _addSub(db, 'Sub $i');
    }

    final results = await db.subscriptionsDao.search(limit: 3);

    expect(results, hasLength(3));
    await db.close();
  });
}

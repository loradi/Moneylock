import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

SubscriptionsCompanion _entry({
  String name = 'Netflix',
  String? brandKey = 'netflix',
  double amount = 15.99,
  String cycle = 'monthly',
  required DateTime nextChargeDate,
  String source = 'manual',
  String? currency,
}) =>
    SubscriptionsCompanion.insert(
      name: name,
      brandKey: Value(brandKey),
      amount: amount,
      cycle: cycle,
      nextChargeDate: nextChargeDate,
      source: Value(source),
      createdAt: DateTime(2026, 1, 1),
      currency: currency == null ? const Value.absent() : Value(currency),
    );

void main() {
  test('add + watchAll returns the inserted subscription', () async {
    final db = _db();
    await db.subscriptionsDao
        .add(_entry(nextChargeDate: DateTime(2026, 9, 1)));

    final rows = await db.subscriptionsDao.watchAll().first;

    expect(rows, hasLength(1));
    expect(rows.first.name, 'Netflix');
    expect(rows.first.brandKey, 'netflix');
    await db.close();
  });

  test('watchAll orders by nextChargeDate ascending', () async {
    final db = _db();
    await db.subscriptionsDao.add(
        _entry(name: 'Later', nextChargeDate: DateTime(2026, 10, 1)));
    await db.subscriptionsDao.add(
        _entry(name: 'Sooner', nextChargeDate: DateTime(2026, 9, 1)));

    final rows = await db.subscriptionsDao.watchAll().first;

    expect(rows.map((r) => r.name).toList(), ['Sooner', 'Later']);
    await db.close();
  });

  test('remove deletes the subscription', () async {
    final db = _db();
    final id = await db.subscriptionsDao
        .add(_entry(nextChargeDate: DateTime(2026, 9, 1)));

    await db.subscriptionsDao.remove(id);

    final rows = await db.subscriptionsDao.watchAll().first;
    expect(rows, isEmpty);
    await db.close();
  });

  test('allForScheduling returns every subscription for the scheduler',
      () async {
    final db = _db();
    await db.subscriptionsDao
        .add(_entry(nextChargeDate: DateTime(2026, 9, 1)));
    await db.subscriptionsDao
        .add(_entry(name: 'Spotify', nextChargeDate: DateTime(2026, 9, 5)));

    final rows = await db.subscriptionsDao.allForScheduling();

    expect(rows, hasLength(2));
    await db.close();
  });

  test('add preserves a non-default source value', () async {
    final db = _db();
    await db.subscriptionsDao.add(_entry(
        name: 'Netflix',
        source: 'suggested',
        nextChargeDate: DateTime(2026, 9, 1)));

    final rows = await db.subscriptionsDao.allForScheduling();

    expect(rows.single.source, 'suggested');
    await db.close();
  });

  test('add preserves a non-default currency value', () async {
    final db = _db();
    await db.subscriptionsDao.add(_entry(
        name: 'Netflix',
        currency: 'EUR',
        nextChargeDate: DateTime(2026, 9, 1)));

    final rows = await db.subscriptionsDao.allForScheduling();

    expect(rows.single.currency, 'EUR');
    await db.close();
  });

  test('rollForwardTo updates nextChargeDate', () async {
    final db = _db();
    final id = await db.subscriptionsDao
        .add(_entry(nextChargeDate: DateTime(2026, 9, 1)));

    await db.subscriptionsDao.rollForwardTo(id, DateTime(2026, 10, 1));

    final rows = await db.subscriptionsDao.allForScheduling();
    expect(rows.single.nextChargeDate, DateTime(2026, 10, 1));
    await db.close();
  });
}

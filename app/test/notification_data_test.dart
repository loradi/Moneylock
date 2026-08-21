import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('notificationsEnabled defaults to true and round-trips', () async {
    final db = _db();
    expect(await db.settingsDao.notificationsEnabled(), isTrue);
    await db.settingsDao.setNotificationsEnabled(false);
    expect(await db.settingsDao.notificationsEnabled(), isFalse);
    await db.settingsDao.setNotificationsEnabled(true);
    expect(await db.settingsDao.notificationsEnabled(), isTrue);
    await db.close();
  });

  test('hasEntrySince is false with no transactions, true after one', () async {
    final db = _db();
    final start = DateTime(2026, 8, 17);
    expect(await db.transactionsDao.hasEntrySince(start), isFalse);
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 10.0,
      currency: 'USD',
      merchant: 'Test',
      category: 'Other',
      source: 'manual',
      rawText: 'test entry',
      timestamp: DateTime(2026, 8, 17, 10),
    ));
    expect(await db.transactionsDao.hasEntrySince(start), isTrue);
    await db.close();
  });

  test('hasEntrySince ignores transactions before the given start', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 10.0,
      currency: 'USD',
      merchant: 'Yesterday',
      category: 'Other',
      source: 'manual',
      rawText: 'yesterday entry',
      timestamp: DateTime(2026, 8, 16, 23, 59),
    ));
    expect(await db.transactionsDao.hasEntrySince(DateTime(2026, 8, 17)), isFalse);
    await db.close();
  });

  test('totalSpentThisPeriod sums across all categories for the month', () async {
    final db = _db();
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 30.0,
      currency: 'USD',
      merchant: 'A',
      category: 'Coffee & Dining',
      source: 'manual',
      rawText: 'a',
      timestamp: DateTime(2026, 8, 5),
    ));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 20.0,
      currency: 'USD',
      merchant: 'B',
      category: 'Groceries',
      source: 'manual',
      rawText: 'b',
      timestamp: DateTime(2026, 8, 20),
    ));
    await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 999.0,
      currency: 'USD',
      merchant: 'C',
      category: 'Other',
      source: 'manual',
      rawText: 'c',
      timestamp: DateTime(2026, 7, 31),
    ));
    expect(await db.transactionsDao.totalSpentThisPeriod('2026-08'), closeTo(50.0, 0.001));
    await db.close();
  });
}

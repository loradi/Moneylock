import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

Future<void> _insert(
  AppDatabase db, {
  required String merchant,
  required String category,
  required double amount,
  required DateTime timestamp,
}) async {
  await db.transactionsDao.insertWithDedup(NewTransaction(
    amount: amount,
    currency: 'USD',
    merchant: merchant,
    category: category,
    source: 'manual',
    rawText: '$merchant $amount',
    timestamp: timestamp,
  ));
}

void main() {
  test('spentByCategoryThisPeriod sums by category within the period', () async {
    final db = _db();
    await _insert(db, merchant: 'A', category: 'Groceries', amount: 10.0, timestamp: DateTime(2026, 8, 5));
    await _insert(db, merchant: 'B', category: 'Groceries', amount: 5.0, timestamp: DateTime(2026, 8, 10));
    await _insert(db, merchant: 'C', category: 'Transport', amount: 20.0, timestamp: DateTime(2026, 8, 15));
    await _insert(db, merchant: 'D', category: 'Groceries', amount: 99.0, timestamp: DateTime(2026, 7, 1));

    final result = await db.transactionsDao.spentByCategoryThisPeriod('2026-08');

    expect(result['Groceries'], 15.0);
    expect(result['Transport'], 20.0);
    expect(result.containsKey('2026-07'), isFalse);
    await db.close();
  });

  test('search filters by category', () async {
    final db = _db();
    await _insert(db, merchant: 'A', category: 'Groceries', amount: 10.0, timestamp: DateTime(2026, 8, 5));
    await _insert(db, merchant: 'B', category: 'Transport', amount: 20.0, timestamp: DateTime(2026, 8, 6));

    final rows = await db.transactionsDao.search(category: 'Groceries');

    expect(rows, hasLength(1));
    expect(rows.single.merchant, 'A');
    await db.close();
  });

  test('search filters by merchant keyword against merchant and rawText', () async {
    final db = _db();
    await _insert(db, merchant: 'Nike Store', category: 'Shopping & E-commerce', amount: 89.99, timestamp: DateTime(2026, 6, 12));
    await _insert(db, merchant: 'Starbucks', category: 'Coffee & Dining', amount: 5.0, timestamp: DateTime(2026, 6, 13));

    final rows = await db.transactionsDao.search(merchantKeyword: 'Nike');

    expect(rows, hasLength(1));
    expect(rows.single.merchant, 'Nike Store');
    await db.close();
  });

  test('search filters by since date', () async {
    final db = _db();
    await _insert(db, merchant: 'Old', category: 'Other', amount: 1.0, timestamp: DateTime(2026, 1, 1));
    await _insert(db, merchant: 'New', category: 'Other', amount: 2.0, timestamp: DateTime(2026, 8, 1));

    final rows = await db.transactionsDao.search(since: DateTime(2026, 6, 1));

    expect(rows, hasLength(1));
    expect(rows.single.merchant, 'New');
    await db.close();
  });

  test('search combines filters and returns empty when nothing matches', () async {
    final db = _db();
    await _insert(db, merchant: 'Nike Store', category: 'Shopping & E-commerce', amount: 89.99, timestamp: DateTime(2026, 6, 12));

    final rows = await db.transactionsDao.search(category: 'Groceries', merchantKeyword: 'Nike');

    expect(rows, isEmpty);
    await db.close();
  });

  test('search orders newest first and respects limit', () async {
    final db = _db();
    await _insert(db, merchant: 'A', category: 'Other', amount: 1.0, timestamp: DateTime(2026, 8, 1));
    await _insert(db, merchant: 'B', category: 'Other', amount: 2.0, timestamp: DateTime(2026, 8, 2));
    await _insert(db, merchant: 'C', category: 'Other', amount: 3.0, timestamp: DateTime(2026, 8, 3));

    final rows = await db.transactionsDao.search(limit: 2);

    expect(rows.map((r) => r.merchant).toList(), ['C', 'B']);
    await db.close();
  });

  test('remove deletes a transaction, and a second call is a harmless no-op', () async {
    final db = _db();
    final outcome = await db.transactionsDao.insertWithDedup(NewTransaction(
      amount: 5.0,
      currency: 'USD',
      merchant: 'Test',
      category: 'Other',
      source: 'manual',
      rawText: 'Test 5.0',
      timestamp: DateTime(2026, 8, 1),
    ));
    final id = outcome.transaction!.id;

    await db.transactionsDao.remove(id);
    final afterFirst = await db.transactionsDao.search();
    expect(afterFirst, isEmpty);

    await db.transactionsDao.remove(id); // no throw
    await db.close();
  });
}

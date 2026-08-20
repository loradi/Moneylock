import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transactions_dao.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

Future<int> _addTx(AppDatabase db) async {
  final outcome = await db.transactionsDao.insertWithDedup(NewTransaction(
    amount: 20.0,
    currency: 'USD',
    merchant: 'Old Store',
    category: 'Other',
    source: 'manual',
    rawText: 'Old Store 20.0',
    timestamp: DateTime.now(),
  ));
  return outcome.transaction!.id;
}

void main() {
  test('updateFields updates only amount when merchant is omitted', () async {
    final db = _db();
    final id = await _addTx(db);

    await db.transactionsDao.updateFields(id, amount: 50.0);

    final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    expect(row.amount, 50.0);
    expect(row.merchant, 'Old Store');
    await db.close();
  });

  test('updateFields updates only merchant when amount is omitted', () async {
    final db = _db();
    final id = await _addTx(db);

    await db.transactionsDao.updateFields(id, merchant: 'New Store');

    final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    expect(row.amount, 20.0);
    expect(row.merchant, 'New Store');
    await db.close();
  });

  test('updateFields updates both fields when both are given', () async {
    final db = _db();
    final id = await _addTx(db);

    await db.transactionsDao.updateFields(id, amount: 50.0, merchant: 'New Store');

    final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    expect(row.amount, 50.0);
    expect(row.merchant, 'New Store');
    await db.close();
  });
}

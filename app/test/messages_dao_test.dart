import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/transaction_summary.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  test('add with no kind defaults to text with a null dataJson', () async {
    final db = _db();
    await db.messagesDao.add('mentor', 'hello');

    final rows = await db.messagesDao.watchAll().first;

    expect(rows.single.kind, 'text');
    expect(rows.single.dataJson, isNull);
    await db.close();
  });

  test('add with transactions stores kind and encodes dataJson', () async {
    final db = _db();
    final summaries = [
      TransactionSummary(
        id: 1,
        merchant: 'Nike',
        amount: 89.99,
        category: 'Shopping & E-commerce',
        timestamp: DateTime(2026, 6, 12),
      ),
    ];

    await db.messagesDao.add(
      'mentor',
      'Found 1 matching "Nike"',
      kind: 'transaction_list',
      transactions: summaries,
    );

    final rows = await db.messagesDao.watchAll().first;
    expect(rows.single.kind, 'transaction_list');
    final decoded = decodeTransactionSummaries(rows.single.dataJson!);
    expect(decoded.single.merchant, 'Nike');
    await db.close();
  });
}

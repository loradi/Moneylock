import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/transaction_csv_backup.dart';
import 'package:moneylock/data/transactions_dao.dart';

import 'helpers/test_database.dart';

void main() {
  test(
    'exports and restores CSV records without duplicating an import',
    () async {
      final source = createTestDatabase();
      final timestamp = DateTime.utc(2026, 9, 1, 14, 30);
      await source.transactionsDao.insertWithDedup(
        NewTransaction(
          amount: 12.5,
          currency: 'CAD',
          merchant: 'A, B "Market"',
          category: 'Groceries',
          source: 'manual',
          rawText: 'A, B "Market" 12.50 CAD',
          timestamp: timestamp,
        ),
      );
      final backup = TransactionCsvBackup();
      final csv = backup.exportRows(await source.transactionsDao.all());
      expect(csv, contains('"A, B ""Market"""'));

      final destination = createTestDatabase();
      final first = await backup.importRows(destination.transactionsDao, csv);
      expect((first.imported, first.duplicates, first.rejected), (1, 0, 0));
      final restored = await destination.transactionsDao.all();
      expect(restored.single.merchant, 'A, B "Market"');
      expect(restored.single.timestamp.toUtc(), timestamp);

      final second = await backup.importRows(destination.transactionsDao, csv);
      expect((second.imported, second.duplicates, second.rejected), (0, 1, 0));
      await source.close();
      await destination.close();
    },
  );

  test('rejects malformed rows while preserving valid CSV records', () async {
    final db = createTestDatabase();
    const csv = '''timestamp,amount,currency,merchant,category,source,raw_text
2026-09-01T14:30:00Z,25,USD,Coffee,Food,manual,Coffee 25
not-a-date,12,USD,Bad,Food,manual,Bad 12''';
    final result = await TransactionCsvBackup().importRows(
      db.transactionsDao,
      csv,
    );
    expect((result.imported, result.duplicates, result.rejected), (1, 0, 1));
    await db.close();
  });
}

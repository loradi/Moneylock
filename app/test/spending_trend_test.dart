import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/insights/spending_trend.dart';

Transaction _transaction({
  required int id,
  required double amount,
  required DateTime timestamp,
}) => Transaction(
  id: id,
  amount: amount,
  currency: 'USD',
  merchant: 'Test',
  category: 'Other',
  source: 'manual',
  rawText: 'Test',
  timestamp: timestamp,
  dedupHash: 'trend-$id',
);

void main() {
  test(
    'returns contiguous chronological months with zeroes for empty months',
    () {
      final trend = buildMonthlySpendingTrend(
        transactions: [
          _transaction(id: 1, amount: 20, timestamp: DateTime(2026, 5, 3)),
          _transaction(id: 2, amount: 35, timestamp: DateTime(2026, 5, 20)),
          _transaction(id: 3, amount: 80, timestamp: DateTime(2026, 8, 10)),
          _transaction(id: 4, amount: 99, timestamp: DateTime(2026, 2, 10)),
        ],
        now: DateTime(2026, 8, 15),
        monthCount: 4,
      );

      expect(trend.map((point) => point.month.month), [5, 6, 7, 8]);
      expect(trend.map((point) => point.total), [55, 0, 0, 80]);
    },
  );
}

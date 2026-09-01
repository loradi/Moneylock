import '../../data/db.dart';

class MonthlySpendPoint {
  final DateTime month;
  final double total;

  const MonthlySpendPoint({required this.month, required this.total});
}

/// Aggregates transactions into a continuous month-by-month series. Empty
/// months remain present as zeroes so the chart's x-axis is actual time.
List<MonthlySpendPoint> buildMonthlySpendingTrend({
  required List<Transaction> transactions,
  DateTime? now,
  int monthCount = 6,
}) {
  assert(monthCount > 0);
  final reference = now ?? DateTime.now();
  final currentMonth = DateTime(reference.year, reference.month);
  final firstMonth = DateTime(
    currentMonth.year,
    currentMonth.month - monthCount + 1,
  );
  final totals = <String, double>{};

  for (final transaction in transactions) {
    final date = transaction.timestamp;
    if (date.isBefore(firstMonth) ||
        !date.isBefore(DateTime(currentMonth.year, currentMonth.month + 1))) {
      continue;
    }
    final key =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
    totals[key] = (totals[key] ?? 0) + transaction.amount;
  }

  return List.generate(monthCount, (index) {
    final month = DateTime(firstMonth.year, firstMonth.month + index);
    final key =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    return MonthlySpendPoint(month: month, total: totals[key] ?? 0);
  });
}

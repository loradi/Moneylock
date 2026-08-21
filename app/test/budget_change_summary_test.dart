import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/budget_change_summary.dart';

void main() {
  test('round-trips a single change through JSON encode/decode', () {
    final original = BudgetChangeSummary(
      category: 'Groceries',
      currentLimit: 300.0,
      proposedLimit: 400.0,
      period: '2026-08',
    );

    final decoded = decodeBudgetChangeSummary(encodeBudgetChangeSummary(original));

    expect(decoded.category, 'Groceries');
    expect(decoded.currentLimit, 300.0);
    expect(decoded.proposedLimit, 400.0);
    expect(decoded.period, '2026-08');
  });
}

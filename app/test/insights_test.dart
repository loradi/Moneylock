import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/insights/insights_agent.dart';

void main() {
  test('genera capsula por categoria dominante con disclaimer', () {
    final caps = generateInsights(BudgetSummary(
      totalSpent: 1000,
      totalLimit: 2000,
      byCategory: {'Coffee & Dining': 600, 'Transport': 400}));
    expect(caps, isNotEmpty);
    final body = caps.first.body;
    expect(body,
        contains('Educational information only, not financial advice.'));
  });
  test('sin gasto -> capsula unica generica', () {
    final caps = generateInsights(
        BudgetSummary(totalSpent: 0, totalLimit: 0, byCategory: {}));
    expect(caps.length, 1);
  });
}
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/budget/plan_scenario.dart';

void main() {
  test(
    'scenario updates daily room and unassigned income without persisting',
    () {
      final result = simulatePlan(
        income: 4000,
        planned: 3000,
        spent: 1200,
        recurring: 300,
        daysLeft: 15,
        incomeAdjustment: 200,
        capAdjustment: -300,
        recurringAdjustment: 100,
      );

      expect(result.income, 4200);
      expect(result.planned, 2700);
      expect(result.unassigned, 1500);
      expect(result.recurring, 400);
      expect(result.safeDailyAmount, closeTo(73.33, 0.01));
    },
  );
}

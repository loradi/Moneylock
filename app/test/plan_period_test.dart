import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/budget/plan_period.dart';

void main() {
  test('weekly periods start on Monday and span seven days', () {
    final date = DateTime(2026, 9, 3); // Thursday

    expect(PlanCycle.weekly.startFor(date), DateTime(2026, 8, 31));
    expect(PlanCycle.weekly.endFor(date), DateTime(2026, 9, 7));
    expect(PlanCycle.weekly.keyFor(date), '2026-08-31');
  });

  test('fortnightly periods have a stable two-week boundary', () {
    final date = DateTime(2026, 9, 3);
    final start = PlanCycle.fortnightly.startFor(date);

    expect(PlanCycle.fortnightly.endFor(date).difference(start).inDays, 14);
    expect(
      PlanCycle.fortnightly.startFor(start.add(const Duration(days: 13))),
      start,
    );
    expect(
      PlanCycle.fortnightly.startFor(start.add(const Duration(days: 14))),
      start.add(const Duration(days: 14)),
    );
  });

  test('monthly periods preserve the existing YYYY-MM storage key', () {
    final date = DateTime(2026, 9, 3);

    expect(PlanCycle.monthly.keyFor(date), '2026-09');
    expect(PlanCycle.monthly.daysFor(date), 30);
  });
}

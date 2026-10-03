import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/dashboard/spending_pace.dart';

void main() {
  test('warns for the category projected to exceed its cap', () {
    final alert = findSpendingPaceAlert(
      spentByCategory: {'Dining': 60, 'Travel': 30},
      limitsByCategory: {'Dining': 100, 'Travel': 80},
      now: DateTime(2026, 4, 15),
    );

    expect(alert, isNotNull);
    expect(alert!.category, 'Dining');
    expect(alert.projectedTotal, 120);
    expect(alert.projectedOverage, 20);
    expect(alert.daysRemaining, 15);
  });

  test('does not warn for a category that is within its monthly pace', () {
    final alert = findSpendingPaceAlert(
      spentByCategory: {'Dining': 45},
      limitsByCategory: {'Dining': 100},
      now: DateTime(2026, 4, 15),
    );

    expect(alert, isNull);
  });

  test('waits until there is enough monthly history to project', () {
    final alert = findSpendingPaceAlert(
      spentByCategory: {'Dining': 20},
      limitsByCategory: {'Dining': 100},
      now: DateTime(2026, 4, 2),
    );

    expect(alert, isNull);
  });

  test('does not replace an already exceeded cap with a pace warning', () {
    final alert = findSpendingPaceAlert(
      spentByCategory: {'Dining': 110},
      limitsByCategory: {'Dining': 100},
      now: DateTime(2026, 4, 15),
    );

    expect(alert, isNull);
  });

  test('projects weekly and biweekly plans from their active period', () {
    final weekly = findSpendingPaceAlert(
      spentByCategory: {'Dining': 80},
      limitsByCategory: {'Dining': 100},
      now: DateTime(2026, 4, 9),
      periodStart: DateTime(2026, 4, 6),
      periodEnd: DateTime(2026, 4, 13),
    );
    final biweekly = findSpendingPaceAlert(
      spentByCategory: {'Dining': 80},
      limitsByCategory: {'Dining': 100},
      now: DateTime(2026, 4, 13),
      periodStart: DateTime(2026, 4, 6),
      periodEnd: DateTime(2026, 4, 20),
    );

    expect(weekly?.projectedTotal, closeTo(140, 0.001));
    expect(weekly?.daysRemaining, 3);
    expect(biweekly?.projectedTotal, closeTo(140, 0.001));
    expect(biweekly?.daysRemaining, 6);
  });
}

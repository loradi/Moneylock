import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/savings_goal.dart';
import 'package:moneylock/features/budget/budget_screen.dart'
    show parseSavingsGoalAmount;

void main() {
  const goal = SavingsGoal(
    name: 'Emergency fund',
    targetAmount: 3000,
    savedAmount: 900,
    currency: 'CAD',
  );

  test('projects a target date from the available contribution each cycle', () {
    final projection = projectSavingsGoal(
      goal: goal,
      contributionPerCycle: 350,
      cycleDays: 14,
      now: DateTime(2026, 9, 1),
    );

    expect(projection.remaining, 2100);
    expect(projection.cyclesRemaining, 6);
    expect(projection.targetDate, DateTime(2026, 11, 24));
  });

  test('does not invent a target date with no contribution available', () {
    final projection = projectSavingsGoal(
      goal: goal,
      contributionPerCycle: 0,
      cycleDays: 30,
      now: DateTime(2026, 9, 1),
    );

    expect(projection.cyclesRemaining, isNull);
    expect(projection.targetDate, isNull);
  });

  test('accepts localized savings-goal amounts', () {
    expect(parseSavingsGoalAmount('1,250.50'), 1250.50);
    expect(parseSavingsGoalAmount('1.250,50'), 1250.50);
    expect(parseSavingsGoalAmount(' 950,25 '), 950.25);
  });
}

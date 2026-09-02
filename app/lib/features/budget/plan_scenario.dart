class PlanScenarioResult {
  const PlanScenarioResult({
    required this.income,
    required this.planned,
    required this.recurring,
    required this.unassigned,
    required this.safeDailyAmount,
  });

  final double income;
  final double planned;
  final double recurring;
  final double unassigned;
  final double safeDailyAmount;
}

PlanScenarioResult simulatePlan({
  required double income,
  required double planned,
  required double spent,
  required double recurring,
  required int daysLeft,
  double incomeAdjustment = 0,
  double capAdjustment = 0,
  double recurringAdjustment = 0,
}) {
  final projectedIncome = (income + incomeAdjustment)
      .clamp(0, double.infinity)
      .toDouble();
  final projectedPlan = (planned + capAdjustment)
      .clamp(0, double.infinity)
      .toDouble();
  final projectedRecurring = (recurring + recurringAdjustment)
      .clamp(0, double.infinity)
      .toDouble();
  final availableUnderCaps = projectedPlan - spent - projectedRecurring;
  return PlanScenarioResult(
    income: projectedIncome,
    planned: projectedPlan,
    recurring: projectedRecurring,
    unassigned: projectedIncome - projectedPlan,
    safeDailyAmount: availableUnderCaps > 0 && daysLeft > 0
        ? availableUnderCaps / daysLeft
        : 0,
  );
}

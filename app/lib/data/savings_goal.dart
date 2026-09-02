class SavingsGoal {
  const SavingsGoal({
    required this.name,
    required this.targetAmount,
    required this.savedAmount,
    required this.currency,
  });

  final String name;
  final double targetAmount;
  final double savedAmount;
  final String currency;
}

class SavingsGoalProjection {
  const SavingsGoalProjection({
    required this.remaining,
    required this.contributionPerCycle,
    required this.cyclesRemaining,
    required this.targetDate,
  });

  final double remaining;
  final double contributionPerCycle;
  final int? cyclesRemaining;
  final DateTime? targetDate;
}

SavingsGoalProjection projectSavingsGoal({
  required SavingsGoal goal,
  required double contributionPerCycle,
  required int cycleDays,
  DateTime? now,
}) {
  final remaining = (goal.targetAmount - goal.savedAmount)
      .clamp(0, double.infinity)
      .toDouble();
  final contribution = contributionPerCycle
      .clamp(0, double.infinity)
      .toDouble();
  if (remaining == 0) {
    return SavingsGoalProjection(
      remaining: 0,
      contributionPerCycle: contribution,
      cyclesRemaining: 0,
      targetDate: now ?? DateTime.now(),
    );
  }
  if (contribution == 0) {
    return SavingsGoalProjection(
      remaining: remaining,
      contributionPerCycle: 0,
      cyclesRemaining: null,
      targetDate: null,
    );
  }
  final cycles = (remaining / contribution).ceil();
  final start = now ?? DateTime.now();
  return SavingsGoalProjection(
    remaining: remaining,
    contributionPerCycle: contribution,
    cyclesRemaining: cycles,
    // DateTime duration arithmetic can cross a DST boundary and land an hour
    // off. A financial target is a calendar date, so construct it directly.
    targetDate: DateTime(
      start.year,
      start.month,
      start.day + cycleDays * cycles,
    ),
  );
}

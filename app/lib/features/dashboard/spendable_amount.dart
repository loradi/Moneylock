/// The portion of a monthly plan that remains flexible after known upcoming
/// recurring charges are set aside.
class SpendableAmount {
  const SpendableAmount({
    required this.dailyAmount,
    required this.availableAfterCommitments,
    required this.recurringCommitments,
  });

  final double dailyAmount;
  final double availableAfterCommitments;
  final double recurringCommitments;
}

/// Calculates a daily amount without treating scheduled recurring charges as
/// flexible spending money.
SpendableAmount calculateSpendableAmount({
  required double totalLimit,
  required double totalSpent,
  required double recurringCommitments,
  required int daysLeft,
}) {
  final availableAfterCommitments =
      totalLimit - totalSpent - recurringCommitments;
  return SpendableAmount(
    dailyAmount: availableAfterCommitments > 0 && daysLeft > 0
        ? availableAfterCommitments / daysLeft
        : 0,
    availableAfterCommitments: availableAfterCommitments,
    recurringCommitments: recurringCommitments,
  );
}

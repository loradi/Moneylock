import 'db.dart';

class ProjectedSubscriptionCharge {
  final Subscription subscription;
  final DateTime chargeDate;

  const ProjectedSubscriptionCharge({
    required this.subscription,
    required this.chargeDate,
  });
}

class MonthlySubscriptionProjection {
  final List<ProjectedSubscriptionCharge> charges;

  const MonthlySubscriptionProjection(this.charges);

  double get total =>
      charges.fold(0, (sum, charge) => sum + charge.subscription.amount);
}

/// Forecasts tracked recurring charges that have not yet reached their charge
/// date in [month]. It is intentionally a subscription forecast, not an
/// asserted account balance or a prediction of untracked spending.
MonthlySubscriptionProjection projectSubscriptionCharges({
  required List<Subscription> subscriptions,
  required DateTime month,
  required String currency,
  DateTime? now,
}) {
  final monthStart = DateTime(month.year, month.month);
  final monthEnd = DateTime(month.year, month.month + 1);
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);

  // Historical subscription dates are not reliable enough to reconstruct, so
  // only project the current month forward or future months.
  if (!monthEnd.isAfter(startOfToday)) {
    return const MonthlySubscriptionProjection([]);
  }
  final windowStart =
      today.year == month.year &&
          today.month == month.month &&
          startOfToday.isAfter(monthStart)
      ? startOfToday
      : monthStart;
  final charges = <ProjectedSubscriptionCharge>[];

  for (final subscription in subscriptions.where(
    (s) => s.currency == currency,
  )) {
    var chargeDate = DateTime(
      subscription.nextChargeDate.year,
      subscription.nextChargeDate.month,
      subscription.nextChargeDate.day,
    );
    while (chargeDate.isBefore(windowStart)) {
      chargeDate = _advanceCycle(chargeDate, subscription.cycle);
    }
    while (chargeDate.isBefore(monthEnd)) {
      charges.add(
        ProjectedSubscriptionCharge(
          subscription: subscription,
          chargeDate: chargeDate,
        ),
      );
      chargeDate = _advanceCycle(chargeDate, subscription.cycle);
    }
  }
  charges.sort((a, b) => a.chargeDate.compareTo(b.chargeDate));
  return MonthlySubscriptionProjection(charges);
}

DateTime _advanceCycle(DateTime date, String cycle) {
  final months = cycle == 'yearly' ? 12 : 1;
  final totalMonths = date.month - 1 + months;
  final year = date.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day.clamp(1, lastDay));
}

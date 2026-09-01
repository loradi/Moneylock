import 'package:flutter/material.dart';

/// A category whose current daily spending rate would exceed its monthly cap.
class SpendingPaceAlert {
  const SpendingPaceAlert({
    required this.category,
    required this.spent,
    required this.limit,
    required this.projectedTotal,
    required this.daysRemaining,
  });

  final String category;
  final double spent;
  final double limit;
  final double projectedTotal;
  final int daysRemaining;

  double get projectedOverage => projectedTotal - limit;
  double get remaining => limit - spent;
}

/// Finds the category most likely to overrun its cap if its daily rate holds.
///
/// The first few days are intentionally ignored because one purchase is not
/// enough signal to make a useful monthly projection. A category must also be
/// tracking at least 15% above its cap to avoid unnecessary warnings.
SpendingPaceAlert? findSpendingPaceAlert({
  required Map<String, double> spentByCategory,
  required Map<String, double> limitsByCategory,
  DateTime? now,
}) {
  final date = now ?? DateTime.now();
  const earliestReliableDay = 4;
  if (date.day < earliestReliableDay) return null;

  final daysInMonth = DateUtils.getDaysInMonth(date.year, date.month);
  SpendingPaceAlert? mostUrgent;

  for (final entry in limitsByCategory.entries) {
    final limit = entry.value;
    final spent = spentByCategory[entry.key] ?? 0;
    if (limit <= 0 || spent <= 0 || spent >= limit) continue;

    final projectedTotal = spent / date.day * daysInMonth;
    final isMateriallyOverPace = projectedTotal > limit * 1.15;
    if (!isMateriallyOverPace) continue;

    final candidate = SpendingPaceAlert(
      category: entry.key,
      spent: spent,
      limit: limit,
      projectedTotal: projectedTotal,
      daysRemaining: daysInMonth - date.day,
    );
    if (mostUrgent == null ||
        candidate.projectedOverage > mostUrgent.projectedOverage) {
      mostUrgent = candidate;
    }
  }

  return mostUrgent;
}

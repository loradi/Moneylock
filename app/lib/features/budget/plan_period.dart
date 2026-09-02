enum PlanCycle {
  weekly('weekly', 'Weekly', 7),
  fortnightly('fortnightly', 'Every 2 weeks', 14),
  monthly('monthly', 'Monthly', 0);

  const PlanCycle(this.storageValue, this.label, this.fixedDays);

  final String storageValue;
  final String label;
  final int fixedDays;

  static PlanCycle fromStorage(String value) => PlanCycle.values.firstWhere(
    (cycle) => cycle.storageValue == value,
    orElse: () => PlanCycle.monthly,
  );

  DateTime startFor(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return switch (this) {
      PlanCycle.monthly => DateTime(day.year, day.month),
      PlanCycle.weekly => day.subtract(Duration(days: day.weekday - 1)),
      PlanCycle.fortnightly => _fortnightStart(day),
    };
  }

  DateTime endFor(DateTime date) {
    final start = startFor(date);
    return switch (this) {
      PlanCycle.monthly => DateTime(start.year, start.month + 1),
      PlanCycle.weekly ||
      PlanCycle.fortnightly => start.add(Duration(days: fixedDays)),
    };
  }

  DateTime shift(DateTime date, int periods) => switch (this) {
    PlanCycle.monthly => DateTime(date.year, date.month + periods),
    PlanCycle.weekly || PlanCycle.fortnightly => startFor(
      date,
    ).add(Duration(days: fixedDays * periods)),
  };

  int daysFor(DateTime date) => switch (this) {
    PlanCycle.monthly => endFor(date).difference(startFor(date)).inDays,
    PlanCycle.weekly || PlanCycle.fortnightly => fixedDays,
  };

  String keyFor(DateTime date) {
    final start = startFor(date);
    if (this == PlanCycle.monthly) {
      return '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}';
    }
    return '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
  }
}

DateTime _fortnightStart(DateTime day) {
  // A stable Monday anchor keeps every two-week plan aligned across app
  // launches without storing an additional date for each user.
  final anchor = DateTime(2024, 1, 1);
  final daysSinceAnchor = day.difference(anchor).inDays;
  final offset = daysSinceAnchor % 14;
  return day.subtract(Duration(days: offset < 0 ? offset + 14 : offset));
}

import 'package:drift/drift.dart';

import 'db.dart';

class BudgetsDao {
  final AppDatabase db;
  BudgetsDao(this.db);

  Future<void> upsert(
    String category,
    double limit,
    String period, {
    String cycle = 'monthly',
    int cycleDays = 30,
    String currency = 'USD',
  }) {
    final companion = BudgetsCompanion.insert(
      category: category,
      monthlyLimit: limit,
      period: period,
      cycle: Value(cycle),
      cycleDays: Value(cycleDays),
      currency: Value(currency),
    );
    return db
        .into(db.budgets)
        .insert(
          companion,
          onConflict: DoUpdate(
            (_) => companion,
            target: [db.budgets.category, db.budgets.period],
          ),
        );
  }

  Future<Map<String, double>> limitsForPeriod(String period) async {
    final rows = await (db.select(
      db.budgets,
    )..where((b) => b.period.equals(period))).get();
    return {for (final r in rows) r.category: r.monthlyLimit};
  }

  /// Copies the category allocations into a new planning month.
  ///
  /// Existing categories in [targetPeriod] are updated; categories that only
  /// exist in the target are deliberately left alone so a user's additions
  /// are never removed by a convenience action.
  Future<int> copyPeriod(
    String sourcePeriod,
    String targetPeriod, {
    required int targetCycleDays,
  }) async {
    final source = await (db.select(
      db.budgets,
    )..where((b) => b.period.equals(sourcePeriod))).get();
    if (source.isEmpty) return 0;

    await db.transaction(() async {
      for (final budget in source) {
        await upsert(
          budget.category,
          budget.monthlyLimit,
          targetPeriod,
          cycle: budget.cycle,
          cycleDays: targetCycleDays,
          currency: budget.currency,
        );
      }
    });
    return source.length;
  }

  Future<List<Budget>> all() => db.select(db.budgets).get();

  Future<void> remove(String category, String period) => (db.delete(
    db.budgets,
  )..where((b) => b.category.equals(category) & b.period.equals(period))).go();
}

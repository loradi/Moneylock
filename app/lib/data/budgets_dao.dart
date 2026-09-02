import 'package:drift/drift.dart';

import 'db.dart';

double convertCurrencyAmount(double amount, double rate) =>
    (amount * rate * 100).roundToDouble() / 100;

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
    final rows = await forPeriod(period);
    return {for (final r in rows) r.category: r.monthlyLimit};
  }

  Future<List<Budget>> forPeriod(String period) =>
      (db.select(db.budgets)..where((b) => b.period.equals(period))).get();

  /// Copies the category allocations into a new planning month.
  ///
  /// Existing categories in [targetPeriod] are updated; categories that only
  /// exist in the target are deliberately left alone so a user's additions
  /// are never removed by a convenience action.
  Future<int> copyPeriod(
    String sourcePeriod,
    String targetPeriod, {
    required int targetCycleDays,
    String? targetCycle,
    String? targetCurrency,
    double multiplier = 1,
  }) async {
    final source = await forPeriod(sourcePeriod);
    if (source.isEmpty) return 0;

    await db.transaction(() async {
      for (final budget in source) {
        await upsert(
          budget.category,
          budget.monthlyLimit * multiplier,
          targetPeriod,
          cycle: targetCycle ?? budget.cycle,
          cycleDays: targetCycleDays,
          currency: targetCurrency ?? budget.currency,
        );
      }
    });
    return source.length;
  }

  Future<void> convertPeriodCurrency(
    String period, {
    required String targetCurrency,
    required double rate,
  }) async {
    if (!rate.isFinite || rate <= 0) {
      throw ArgumentError.value(rate, 'rate', 'must be a positive number');
    }
    final rows = await forPeriod(period);
    await db.transaction(() async {
      for (final budget in rows) {
        await (db.update(
          db.budgets,
        )..where((b) => b.id.equals(budget.id))).write(
          BudgetsCompanion(
            monthlyLimit: Value(
              convertCurrencyAmount(budget.monthlyLimit, rate),
            ),
            currency: Value(targetCurrency),
          ),
        );
      }
    });
  }

  Future<List<Budget>> all() => db.select(db.budgets).get();

  Future<void> remove(String category, String period) => (db.delete(
    db.budgets,
  )..where((b) => b.category.equals(category) & b.period.equals(period))).go();
}

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
  }) => db
      .into(db.budgets)
      .insertOnConflictUpdate(
        BudgetsCompanion.insert(
          category: category,
          monthlyLimit: limit,
          period: period,
          cycle: Value(cycle),
          cycleDays: Value(cycleDays),
          currency: Value(currency),
        ),
      );

  Future<Map<String, double>> limitsForPeriod(String period) async {
    final rows = await (db.select(
      db.budgets,
    )..where((b) => b.period.equals(period))).get();
    return {for (final r in rows) r.category: r.monthlyLimit};
  }

  Future<List<Budget>> all() => db.select(db.budgets).get();

  Future<void> remove(String category, String period) => (db.delete(
    db.budgets,
  )..where((b) => b.category.equals(category) & b.period.equals(period))).go();
}

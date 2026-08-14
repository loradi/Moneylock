import 'db.dart';

class BudgetsDao {
  final AppDatabase db;
  BudgetsDao(this.db);

  Future<void> upsert(String category, double limit, String period) =>
      db.into(db.budgets).insertOnConflictUpdate(BudgetsCompanion.insert(
          category: category, monthlyLimit: limit, period: period));

  Future<Map<String, double>> limitsForPeriod(String period) async {
    final rows = await (db.select(db.budgets)
          ..where((b) => b.period.equals(period))).get();
    return {for (final r in rows) r.category: r.monthlyLimit};
  }
}
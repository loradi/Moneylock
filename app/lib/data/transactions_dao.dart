import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'db.dart';

class NewTransaction {
  final double amount;
  final String currency;
  final String merchant;
  final String category;
  final String source;
  final String rawText;
  final DateTime timestamp;
  NewTransaction({
    required this.amount,
    required this.currency,
    required this.merchant,
    required this.category,
    required this.source,
    required this.rawText,
    required this.timestamp,
  });
}

class TransactionsDao {
  final AppDatabase db;
  TransactionsDao(this.db);

  String dedupHash(String rawText, DateTime ts) {
    final normalized = rawText.toLowerCase().trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return sha256
        .convert(utf8.encode('$normalized|${ts.toUtc().toIso8601String()}'))
        .toString();
  }

  Future<({Transaction? transaction, bool inserted})> insertWithDedup(
    NewTransaction t,
  ) async {
    final hash = dedupHash(t.rawText, t.timestamp);
    final existing = await (db.select(
      db.transactions,
    )..where((x) => x.dedupHash.equals(hash))).getSingleOrNull();
    if (existing != null) return (transaction: existing, inserted: false);
    final id = await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            amount: t.amount,
            currency: Value(t.currency),
            merchant: Value(t.merchant),
            category: Value(t.category),
            source: t.source,
            rawText: t.rawText,
            timestamp: t.timestamp,
            dedupHash: hash,
          ),
        );
    final row = await (db.select(
      db.transactions,
    )..where((x) => x.id.equals(id))).getSingle();
    return (transaction: row, inserted: true);
  }

  Future<double> categorySpentThisPeriod(String category, String period) async {
    final start = DateTime.parse('$period-01T00:00:00');
    final end = DateTime(start.year, start.month + 1, 1);
    final rows =
        await (db.select(db.transactions)..where(
              (t) =>
                  t.category.equals(category) &
                  t.timestamp.isBiggerOrEqualValue(start) &
                  t.timestamp.isSmallerThanValue(end),
            ))
            .get();
    return rows.fold<double>(0.0, (sum, r) => sum + r.amount);
  }

  Future<bool> hasEntrySince(DateTime start) async {
    final row = await (db.select(db.transactions)
          ..where((t) => t.timestamp.isBiggerOrEqualValue(start))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<double> totalSpentThisPeriod(String period) async {
    final start = DateTime.parse('$period-01T00:00:00');
    final end = DateTime(start.year, start.month + 1, 1);
    final rows = await (db.select(db.transactions)..where(
          (t) =>
              t.timestamp.isBiggerOrEqualValue(start) &
              t.timestamp.isSmallerThanValue(end),
        ))
        .get();
    return rows.fold<double>(0.0, (sum, r) => sum + r.amount);
  }

  Future<List<Transaction>> recent(int n) async {
    final q = db.select(db.transactions)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
    q.limit(n);
    return q.get();
  }

  Future<Transaction?> updateMostRecentCategory(String category) async {
    final latest = await recent(1);
    if (latest.isEmpty) return null;
    final transaction = latest.first;
    await (db.update(db.transactions)
          ..where((row) => row.id.equals(transaction.id)))
        .write(TransactionsCompanion(category: Value(category)));
    return transaction.copyWith(category: category);
  }

  Future<Map<String, double>> spentByCategoryThisPeriod(String period) async {
    final start = DateTime.parse('$period-01T00:00:00');
    final end = DateTime(start.year, start.month + 1, 1);
    final rows = await (db.select(db.transactions)..where(
          (t) =>
              t.timestamp.isBiggerOrEqualValue(start) &
              t.timestamp.isSmallerThanValue(end),
        ))
        .get();
    final result = <String, double>{};
    for (final r in rows) {
      result[r.category] = (result[r.category] ?? 0) + r.amount;
    }
    return result;
  }

  Future<List<Transaction>> search({
    String? category,
    String? merchantKeyword,
    DateTime? since,
    int limit = 20,
  }) async {
    final q = db.select(db.transactions)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
      ..limit(limit);
    if (category != null) {
      q.where((t) => t.category.equals(category));
    }
    if (merchantKeyword != null) {
      final pattern = '%$merchantKeyword%';
      q.where((t) => t.merchant.like(pattern) | t.rawText.like(pattern));
    }
    if (since != null) {
      q.where((t) => t.timestamp.isBiggerOrEqualValue(since));
    }
    return q.get();
  }

  Future<void> remove(int id) =>
      (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();
}

import 'package:drift/drift.dart';

import 'db.dart';

class SubscriptionsDao {
  final AppDatabase db;
  SubscriptionsDao(this.db);

  Stream<List<Subscription>> watchAll() =>
      (db.select(db.subscriptions)
            ..where((s) => s.isActive.equals(true))
            ..orderBy([(s) => OrderingTerm.asc(s.nextChargeDate)]))
          .watch();

  Future<int> add(SubscriptionsCompanion entry) =>
      db.into(db.subscriptions).insert(entry);

  Future<void> update(int id, SubscriptionsCompanion changes) => (db.update(
    db.subscriptions,
  )..where((s) => s.id.equals(id))).write(changes);

  Future<void> remove(int id) =>
      (db.update(db.subscriptions)..where((s) => s.id.equals(id))).write(
        const SubscriptionsCompanion(isActive: Value(false)),
      );

  Future<List<Subscription>> allForScheduling() => (db.select(
    db.subscriptions,
  )..where((s) => s.isActive.equals(true))).get();

  Future<List<Subscription>> allForSync() => db.select(db.subscriptions).get();

  Future<void> rollForwardTo(int id, DateTime newNextChargeDate) => update(
    id,
    SubscriptionsCompanion(nextChargeDate: Value(newNextChargeDate)),
  );

  Future<List<Subscription>> search({
    String? nameKeyword,
    int limit = 20,
  }) async {
    final q = db.select(db.subscriptions)
      ..where((s) => s.isActive.equals(true))
      ..orderBy([(s) => OrderingTerm.asc(s.nextChargeDate)])
      ..limit(limit);
    if (nameKeyword != null) {
      q.where((s) => s.name.like('%$nameKeyword%'));
    }
    return q.get();
  }

  Future<void> upsertForSync({
    required String name,
    required String? brandKey,
    required double amount,
    required String currency,
    required String cycle,
    required DateTime nextChargeDate,
    required String source,
    required DateTime createdAt,
    required bool isActive,
  }) async {
    final existing =
        await (db.select(db.subscriptions)
              ..where((row) => row.name.equals(name) & row.cycle.equals(cycle)))
            .getSingleOrNull();
    final values = SubscriptionsCompanion(
      name: Value(name),
      brandKey: Value(brandKey),
      amount: Value(amount),
      currency: Value(currency),
      cycle: Value(cycle),
      nextChargeDate: Value(nextChargeDate),
      source: Value(source),
      createdAt: Value(createdAt),
      isActive: Value(isActive),
    );
    if (existing == null) {
      await db
          .into(db.subscriptions)
          .insert(
            SubscriptionsCompanion.insert(
              name: name,
              amount: amount,
              cycle: cycle,
              nextChargeDate: nextChargeDate,
              createdAt: createdAt,
              brandKey: Value(brandKey),
              currency: Value(currency),
              source: Value(source),
              isActive: Value(isActive),
            ),
          );
      return;
    }
    await (db.update(
      db.subscriptions,
    )..where((row) => row.id.equals(existing.id))).write(values);
  }
}

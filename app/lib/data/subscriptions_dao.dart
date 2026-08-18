import 'package:drift/drift.dart';

import 'db.dart';

class SubscriptionsDao {
  final AppDatabase db;
  SubscriptionsDao(this.db);

  Stream<List<Subscription>> watchAll() =>
      (db.select(db.subscriptions)
            ..orderBy([(s) => OrderingTerm.asc(s.nextChargeDate)]))
          .watch();

  Future<int> add(SubscriptionsCompanion entry) =>
      db.into(db.subscriptions).insert(entry);

  Future<void> update(int id, SubscriptionsCompanion changes) =>
      (db.update(db.subscriptions)..where((s) => s.id.equals(id)))
          .write(changes);

  Future<void> remove(int id) =>
      (db.delete(db.subscriptions)..where((s) => s.id.equals(id))).go();

  Future<List<Subscription>> allForScheduling() =>
      db.select(db.subscriptions).get();

  Future<void> rollForwardTo(int id, DateTime newNextChargeDate) => update(
        id,
        SubscriptionsCompanion(nextChargeDate: Value(newNextChargeDate)),
      );
}

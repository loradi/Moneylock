import 'package:drift/drift.dart';

import 'db.dart';

class CategoriesDao {
  final AppDatabase db;
  CategoriesDao(this.db);

  Future<List<Category>> all() =>
      (db.select(db.categories)
            ..where((c) => c.isActive.equals(true))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();

  Stream<List<Category>> watchAll() =>
      (db.select(db.categories)
            ..where((c) => c.isActive.equals(true))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .watch();

  Future<void> add(String name) => db
      .into(db.categories)
      .insertOnConflictUpdate(
        CategoriesCompanion.insert(
          name: name.trim(),
          isDefault: const Value(false),
        ),
      );

  Future<void> remove(String name) =>
      (db.update(db.categories)..where((c) => c.name.equals(name))).write(
        const CategoriesCompanion(isActive: Value(false)),
      );
}

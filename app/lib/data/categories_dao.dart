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

  Future<void> ensureDefaults() async {
    for (final name in defaultCategoryNames) {
      await db
          .into(db.categories)
          .insertOnConflictUpdate(
            CategoriesCompanion.insert(
              name: name,
              isDefault: const Value(true),
            ),
          );
    }
  }

  Future<void> add(String name) => db
      .into(db.categories)
      .insertOnConflictUpdate(
        CategoriesCompanion.insert(
          name: name.trim(),
          isActive: const Value(true),
          isDefault: const Value(false),
        ),
      );

  Future<void> remove(String name) =>
      (db.update(db.categories)..where((c) => c.name.equals(name))).write(
        const CategoriesCompanion(isActive: Value(false)),
      );
}

const defaultCategoryNames = [
  'Coffee & Dining',
  'Groceries',
  'Transport',
  'Entertainment',
  'Shopping & E-commerce',
  'Bills & Utilities',
  'Health',
  'Tech',
  'Travel',
  'Other',
];

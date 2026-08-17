import 'dart:async';

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

  Future<void> ensureDefaults() => db.batch(
    (batch) => batch.insertAll(
      db.categories,
      [
        for (final name in defaultCategoryNames)
          CategoriesCompanion.insert(name: name, isDefault: const Value(true)),
      ],
      mode: InsertMode.insertOrIgnore,
    ),
  );

  Future<void> add(String name) {
    final companion = CategoriesCompanion.insert(
      name: name.trim(),
      isActive: const Value(true),
      isDefault: const Value(false),
    );
    return db
        .into(db.categories)
        .insert(
          companion,
          onConflict: DoUpdate(
            (_) => companion,
            target: [db.categories.name],
          ),
        );
  }

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

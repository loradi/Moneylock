import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/categories_dao.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test(
      'upgrading from schema v3 with pre-existing categories does not throw',
      () async {
    final file = File(
      '${Directory.systemTemp.path}/migration_test_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );

    // First open runs onCreate at schemaVersion 4: creates all tables and
    // inserts the 10 default categories.
    final seedDb = AppDatabase.forTesting(NativeDatabase(file));
    await seedDb.categoriesDao.all();
    // Force the on-disk version back to 3 so the next open replays the
    // from<4 migration step against a database that already has
    // categories populated -- the exact scenario that used to throw
    // "UNIQUE constraint failed: categories.name".
    await seedDb.customStatement('PRAGMA user_version = 3');
    await seedDb.close();

    final upgradedDb = AppDatabase.forTesting(NativeDatabase(file));
    final categories = await upgradedDb.categoriesDao.all();
    expect(categories.length, defaultCategoryNames.length);
    await upgradedDb.close();

    await file.delete();
  });
}

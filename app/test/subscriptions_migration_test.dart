import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('upgrading from schema v4 creates the subscriptions table', () async {
    final file = File(
      '${Directory.systemTemp.path}/subs_migration_test_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );

    final seedDb = AppDatabase.forTesting(NativeDatabase(file));
    await seedDb.categoriesDao.all(); // forces onCreate to run at schemaVersion 5
    await seedDb.customStatement('DROP TABLE subscriptions');
    // Also undo the v6 mentor_messages columns: onCreate already includes
    // them, so leaving them in place would make the from<6 migration step
    // collide with columns that already exist when this test upgrades past it.
    await seedDb.customStatement('ALTER TABLE mentor_messages DROP COLUMN kind');
    await seedDb.customStatement('ALTER TABLE mentor_messages DROP COLUMN data_json');
    await seedDb.customStatement('PRAGMA user_version = 4');
    await seedDb.close();

    final upgradedDb = AppDatabase.forTesting(NativeDatabase(file));
    final rows = await upgradedDb.subscriptionsDao.allForScheduling();
    expect(rows, isEmpty); // does not throw -- table exists

    await upgradedDb.close();
    await file.delete();
  });
}

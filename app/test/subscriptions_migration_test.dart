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
    await seedDb.customStatement('PRAGMA user_version = 4');
    await seedDb.close();

    final upgradedDb = AppDatabase.forTesting(NativeDatabase(file));
    final rows = await upgradedDb.subscriptionsDao.allForScheduling();
    expect(rows, isEmpty); // does not throw -- table exists

    await upgradedDb.close();
    await file.delete();
  });
}

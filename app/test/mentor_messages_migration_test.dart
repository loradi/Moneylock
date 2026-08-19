import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('upgrading from schema v5 adds kind and dataJson to mentor_messages', () async {
    final file = File(
      '${Directory.systemTemp.path}/mentor_messages_migration_test_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );

    final seedDb = AppDatabase.forTesting(NativeDatabase(file));
    await seedDb.categoriesDao.all(); // forces onCreate to run at schemaVersion 6
    await seedDb.customStatement('ALTER TABLE mentor_messages DROP COLUMN kind');
    await seedDb.customStatement('ALTER TABLE mentor_messages DROP COLUMN data_json');
    await seedDb.customStatement('PRAGMA user_version = 5');
    await seedDb.close();

    final upgradedDb = AppDatabase.forTesting(NativeDatabase(file));
    await upgradedDb.messagesDao.add('mentor', 'hi'); // does not throw -- columns exist
    final rows = await upgradedDb.messagesDao.watchAll().first;
    expect(rows.single.kind, 'text');

    await upgradedDb.close();
    await file.delete();
  });
}

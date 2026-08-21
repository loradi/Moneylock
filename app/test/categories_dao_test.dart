import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/categories_dao.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('ensureDefaults es idempotente y no lanza en conflicto de nombre', () async {
    final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
    await db.categoriesDao.ensureDefaults();
    await db.categoriesDao.ensureDefaults();
    final rows = await db.categoriesDao.all();
    expect(rows.length, defaultCategoryNames.length);
    await db.close();
  });

  test('add reactiva una categoria previamente removida en vez de lanzar', () async {
    final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
    await db.categoriesDao.add('Pets');
    await db.categoriesDao.remove('Pets');
    await db.categoriesDao.add('Pets');
    final rows = await db.categoriesDao.all();
    expect(rows.where((c) => c.name == 'Pets' && c.isActive), hasLength(1));
    await db.close();
  });

  test('remove marca una categoria como inactiva y ya no aparece en all()', () async {
    final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
    await db.categoriesDao.add('Pets');
    await db.categoriesDao.remove('Pets');
    final rows = await db.categoriesDao.all();
    expect(rows.where((c) => c.name == 'Pets'), isEmpty);
    await db.close();
  });
}

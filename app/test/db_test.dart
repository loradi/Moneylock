import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('settings guarda y recupera mentor tone', () async {
    final db = AppDatabase.forTesting(
        driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));
    await db.settingsDao.setMentorTone('friendly_coach');
    expect(await db.settingsDao.mentorTone(), 'friendly_coach');
    await db.close();
  });
}

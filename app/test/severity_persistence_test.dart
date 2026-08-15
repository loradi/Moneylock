import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

void main() {
  test('mensaje del mentor persiste su severidad', () async {
    final db = AppDatabase.forTesting(
      driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'),
    );
    addTearDown(db.close);

    await db.messagesDao.add(
      'mentor',
      'You are over budget.',
      severity: 'alert',
    );

    final msg = (await db.messagesDao.watchAll().first).single;
    expect(msg.severity, 'alert');
  });
}

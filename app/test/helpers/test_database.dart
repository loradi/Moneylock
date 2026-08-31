import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';

AppDatabase createTestDatabase() =>
    AppDatabase.forTesting(NativeDatabase.memory());

Future<void> disposeTestDatabase(
  WidgetTester tester,
  AppDatabase database,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await database.close();
}

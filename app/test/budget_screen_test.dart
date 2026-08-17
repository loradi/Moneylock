import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/budget/budget_screen.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

Future<AppDatabase> _pumpBudgetScreen(WidgetTester tester) async {
  final db = _db();
  await db.categoriesDao.ensureDefaults();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: BudgetScreen()),
    ),
  );
  try {
    await tester.pumpAndSettle(const Duration(seconds: 3));
  } catch (_) {
    // If settle times out, just pump once more
    await tester.pump();
  }
  return db;
}

void main() {
  testWidgets('tapping outside a focused field dismisses the keyboard',
      (tester) async {
    final db = await _pumpBudgetScreen(tester);

    await tester.tap(find.widgetWithText(TextField, 'No cap').first);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('CATEGORY CAPS'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);

    await db.close();
  });
}

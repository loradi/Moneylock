import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/budget/budget_screen.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

const _testCategories = [
  Category(id: 1, name: 'Bills & Utilities', isActive: true, isDefault: true),
  Category(id: 2, name: 'Coffee & Dining', isActive: true, isDefault: true),
];

/// Pumps [BudgetScreen] with a real (test) database for writes, but a
/// mocked `categoriesProvider` for the category list.
///
/// `categoriesProvider` normally awaits a real native DB round-trip (via
/// drift_flutter's background isolate) before its first emission. Flutter's
/// widget-test zone fakes the clock for animations/timers but does not
/// drive that kind of real async I/O forward on its own — confirmed by
/// direct reproduction, an `AsyncLoading` provider never schedules a new
/// frame, so `pumpAndSettle()` "settles" while the real isolate round-trip
/// is still pending, sometimes for the full 10-minute test timeout.
/// Overriding `categoriesProvider` directly with a synchronous `Stream`
/// sidesteps that native round-trip entirely for list rendering, while
/// `appDatabaseProvider` stays real so `_save`/`_removeCategory` still
/// perform genuine DB writes that tests can verify.
Future<AppDatabase> _pumpBudgetScreen(WidgetTester tester) async {
  final db = _db();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        categoriesProvider.overrideWith((ref) => Stream.value(_testCategories)),
      ],
      child: const MaterialApp(home: BudgetScreen()),
    ),
  );
  await tester.pumpAndSettle();
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
  });
}

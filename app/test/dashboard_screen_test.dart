import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/dashboard/dashboard_screen.dart';
import 'package:moneylock/features/insights/insights_agent.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  testWidgets('renders the "nothing this week" empty state when history is older than 7 days',
      (tester) async {
    final db = _db();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          transactionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          budgetSummaryProvider.overrideWith((ref) => Stream.value(
                BudgetSummary(totalSpent: 0, totalLimit: 0, byCategory: {}, byCategoryLimits: {}),
              )),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No transactions yet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}

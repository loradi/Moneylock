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

Transaction _tx({required int id, required DateTime timestamp}) => Transaction(
      id: id,
      amount: 1.0,
      currency: 'USD',
      merchant: 'Test',
      category: 'Other',
      source: 'manual',
      rawText: 'Test',
      timestamp: timestamp,
      dedupHash: 'hash-$id',
    );

void main() {
  testWidgets('renders "No transactions yet" when there is no history at all',
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

  testWidgets('renders "Nothing this week" when history exists but is older than 7 days',
      (tester) async {
    final db = _db();
    final old = _tx(id: 1, timestamp: DateTime.now().subtract(const Duration(days: 10)));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          transactionsStreamProvider.overrideWith((ref) => Stream.value([old])),
          budgetSummaryProvider.overrideWith((ref) => Stream.value(
                BudgetSummary(totalSpent: 0, totalLimit: 0, byCategory: {}, byCategoryLimits: {}),
              )),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing this week'), findsOneWidget);
    expect(find.text('No transactions yet'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}

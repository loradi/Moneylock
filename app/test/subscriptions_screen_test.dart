import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/features/subscriptions/subscriptions_screen.dart';
import 'package:moneylock/providers.dart';

AppDatabase _db() => AppDatabase.forTesting(
    driftDatabase(name: 'test_${DateTime.now().microsecondsSinceEpoch}'));

void main() {
  testWidgets('renders the empty state with no subscriptions', (tester) async {
    final db = _db();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          subscriptionsProvider.overrideWith((ref) => Stream.value(const [])),
          transactionsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          dismissedSubscriptionSuggestionsProvider.overrideWith((ref) => Future.value(const {})),
        ],
        child: const MaterialApp(home: SubscriptionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Subscriptions'), findsOneWidget);
    expect(find.text('No subscriptions tracked yet. Tap + to add one.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() => db.close());
  });
}

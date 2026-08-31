import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/subscriptions/subscriptions_screen.dart';
import 'package:moneylock/providers.dart';

import 'helpers/test_database.dart';

void main() {
  testWidgets('renders the empty state with no subscriptions', (tester) async {
    final db = createTestDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          subscriptionsProvider.overrideWith((ref) => Stream.value(const [])),
          transactionsStreamProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          dismissedSubscriptionSuggestionsProvider.overrideWith(
            (ref) => Future.value(const {}),
          ),
        ],
        child: const MaterialApp(home: SubscriptionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Subscriptions'), findsOneWidget);
    expect(
      find.text('No subscriptions tracked yet. Tap + to add one.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await disposeTestDatabase(tester, db);
  });
}

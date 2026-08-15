import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moneylock/features/insights/insights_agent.dart';
import 'package:moneylock/main.dart';
import 'package:moneylock/providers.dart';

void main() {
  testWidgets('shell renders 3 tabs and mentor FAB opens chat', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionsStreamProvider
              .overrideWith((ref) => Stream.value(const [])),
          messagesStreamProvider
              .overrideWith((ref) => Stream.value(const [])),
          budgetSummaryProvider.overrideWith((ref) => Stream.value(
              BudgetSummary(totalSpent: 0, totalLimit: 0, byCategory: {}))),
          mentorToneProvider.overrideWith((ref) async => 'strict_ramsey'),
        ],
        child: const MoneylockApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    expect(find.text('Chat'), findsNothing);

    await tester.tap(find.byIcon(Icons.smart_toy));
    await tester.pumpAndSettle();
    expect(find.text('Your money mentor'), findsOneWidget);
  });
}

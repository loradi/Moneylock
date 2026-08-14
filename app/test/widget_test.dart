import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moneylock/features/insights/insights_agent.dart';
import 'package:moneylock/main.dart';
import 'package:moneylock/providers.dart';

void main() {
  testWidgets('app shell renders dashboard with 4 tabs', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        transactionsStreamProvider
            .overrideWith((ref) => Stream.value(const [])),
        messagesStreamProvider
            .overrideWith((ref) => Stream.value(const [])),
        budgetSummaryProvider.overrideWith((ref) => Stream.value(
            BudgetSummary(
                totalSpent: 0, totalLimit: 0, byCategory: {}))),
        mentorToneProvider.overrideWith((ref) async => 'strict_ramsey'),
      ],
      child: const MoneylockApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Moneylock'), findsWidgets);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Recent transactions'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Mentor tone'), findsOneWidget);
    expect(find.text('Strict'), findsOneWidget);
    expect(find.text('Budgets'), findsOneWidget);

    await tester.drag(find.text('Budgets'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('On-device model'), findsOneWidget);
    expect(find.text('Test microphone'), findsOneWidget);
  });
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/onboarding/onboarding_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: OnboardingScreen(
          onComplete: () {},
          onOpenBudget: () {},
          onOpenSubscriptions: () {},
          onOpenChat: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('steps through Welcome -> Meet Vector -> Setup checklist -> Back', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Build a clearer relationship with your money.'), findsOneWidget);
    expect(find.text('Back'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Meet Vector'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your setup checklist'), findsOneWidget);
    expect(find.text('Add your first subscription'), findsOneWidget);
    expect(find.text('Start using Moneylock'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Meet Vector'), findsOneWidget);
  });

  testWidgets('tapping a checklist item invokes its callback without touching the DB', (
    tester,
  ) async {
    var subscriptionsOpened = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OnboardingScreen(
            onComplete: () {},
            onOpenBudget: () {},
            onOpenSubscriptions: () => subscriptionsOpened = true,
            onOpenChat: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add your first subscription'));
    await tester.pumpAndSettle();

    expect(subscriptionsOpened, true);
  });
}

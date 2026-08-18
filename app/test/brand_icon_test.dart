import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/widgets/brand_icon.dart';

void main() {
  testWidgets('known brandKey renders the curated icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SubscriptionAvatar(brandKey: 'netflix', name: 'Netflix'),
    ));

    expect(find.byIcon(brandIcons['netflix']!.icon), findsOneWidget);
  });

  testWidgets('unknown brandKey falls back to an initial avatar',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SubscriptionAvatar(brandKey: null, name: 'Gym Membership'),
    ));

    expect(find.text('G'), findsOneWidget);
  });

  testWidgets('brandKey not present in the curated set also falls back',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SubscriptionAvatar(brandKey: 'not-a-real-brand', name: 'Zed'),
    ));

    expect(find.text('Z'), findsOneWidget);
  });

  test('curated set has at least 15 brands', () {
    expect(brandIcons.length, greaterThanOrEqualTo(15));
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:moneylock/main.dart';

void main() {
  testWidgets('HomeScreen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MoneylockApp());

    expect(find.text('Moneylock'), findsWidgets);
    expect(find.text('Home'), findsOneWidget);
  });
}

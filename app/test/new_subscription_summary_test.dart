import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/new_subscription_summary.dart';

void main() {
  test('round-trips through JSON encode/decode', () {
    final original = NewSubscriptionSummary(
      name: 'Netflix',
      amount: 30.0,
      nextChargeDate: DateTime(2026, 9, 20),
    );

    final decoded = decodeNewSubscriptionSummary(encodeNewSubscriptionSummary(original));

    expect(decoded.name, 'Netflix');
    expect(decoded.amount, 30.0);
    expect(decoded.nextChargeDate, DateTime(2026, 9, 20));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/subscription_edit_summary.dart';
import 'package:moneylock/data/subscription_summary.dart';

void main() {
  test('round-trips through JSON encode/decode', () {
    final original = SubscriptionEditSummary(
      subscription: SubscriptionSummary(
        id: 1,
        name: 'Netflix',
        brandKey: 'netflix',
        amount: 15.99,
        currency: 'USD',
        cycle: 'monthly',
        nextChargeDate: DateTime(2026, 9, 1),
      ),
      newAmount: 18.99,
    );

    final decoded = decodeSubscriptionEditSummary(encodeSubscriptionEditSummary(original));

    expect(decoded.subscription.name, 'Netflix');
    expect(decoded.newAmount, 18.99);
  });
}

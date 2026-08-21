import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/subscription_summary.dart';

void main() {
  test('round-trips through JSON encode/decode', () {
    final original = [
      SubscriptionSummary(
        id: 1,
        name: 'Netflix',
        brandKey: 'netflix',
        amount: 15.99,
        currency: 'USD',
        cycle: 'monthly',
        nextChargeDate: DateTime(2026, 9, 1),
      ),
      SubscriptionSummary(
        id: 2,
        name: 'Adobe Creative Cloud',
        brandKey: null,
        amount: 599.88,
        currency: 'USD',
        cycle: 'yearly',
        nextChargeDate: DateTime(2027, 1, 15),
      ),
    ];

    final decoded = decodeSubscriptionSummaries(encodeSubscriptionSummaries(original));

    expect(decoded, hasLength(2));
    expect(decoded[0].name, 'Netflix');
    expect(decoded[0].brandKey, 'netflix');
    expect(decoded[1].brandKey, isNull);
    expect(decoded[1].cycle, 'yearly');
    expect(decoded[1].nextChargeDate, DateTime(2027, 1, 15));
  });
}

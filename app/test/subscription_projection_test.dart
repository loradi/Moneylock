import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/db.dart';
import 'package:moneylock/data/subscription_projection.dart';

Subscription _subscription({
  required int id,
  required String name,
  required double amount,
  required String cycle,
  required DateTime nextChargeDate,
  String currency = 'USD',
}) => Subscription(
  id: id,
  name: name,
  brandKey: null,
  amount: amount,
  currency: currency,
  cycle: cycle,
  nextChargeDate: nextChargeDate,
  source: 'manual',
  createdAt: DateTime(2026),
  isActive: true,
);

void main() {
  test(
    'projects only the recurring charges inside a weekly planning window',
    () {
      final subscriptions = [
        _subscription(
          id: 1,
          name: 'Music',
          amount: 10,
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 3),
        ),
        _subscription(
          id: 2,
          name: 'Video',
          amount: 15,
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 10),
        ),
      ];

      final projection = projectSubscriptionChargesInRange(
        subscriptions: subscriptions,
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 8),
        currency: 'USD',
        now: DateTime(2026, 9, 1),
      );

      expect(projection.charges, hasLength(1));
      expect(projection.charges.single.subscription.name, 'Music');
    },
  );
  test('projects only upcoming charges in the selected current month', () {
    final projection = projectSubscriptionCharges(
      subscriptions: [
        _subscription(
          id: 1,
          name: 'Netflix',
          amount: 16,
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 3),
        ),
        _subscription(
          id: 2,
          name: 'Gym',
          amount: 50,
          cycle: 'monthly',
          nextChargeDate: DateTime(2026, 9, 1),
        ),
        _subscription(
          id: 3,
          name: 'Annual storage',
          amount: 100,
          cycle: 'yearly',
          nextChargeDate: DateTime(2026, 9, 20),
        ),
      ],
      month: DateTime(2026, 9),
      currency: 'USD',
      now: DateTime(2026, 9, 2, 9),
    );

    expect(projection.charges.map((c) => c.subscription.name), [
      'Netflix',
      'Annual storage',
    ]);
    expect(projection.total, 116);
  });

  test(
    'advances recurring charges into a future month and filters currency',
    () {
      final projection = projectSubscriptionCharges(
        subscriptions: [
          _subscription(
            id: 1,
            name: 'Netflix',
            amount: 16,
            cycle: 'monthly',
            nextChargeDate: DateTime(2026, 9, 3),
          ),
          _subscription(
            id: 2,
            name: 'Canadian service',
            amount: 20,
            cycle: 'monthly',
            currency: 'CAD',
            nextChargeDate: DateTime(2026, 10, 4),
          ),
        ],
        month: DateTime(2026, 11),
        currency: 'USD',
        now: DateTime(2026, 9, 2),
      );

      expect(projection.charges, hasLength(1));
      expect(projection.charges.single.chargeDate, DateTime(2026, 11, 3));
      expect(projection.total, 16);
    },
  );
}

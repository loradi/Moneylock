import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/dashboard/spendable_amount.dart';

void main() {
  test(
    'reserves upcoming recurring charges before dividing daily spending',
    () {
      final amount = calculateSpendableAmount(
        totalLimit: 1000,
        totalSpent: 400,
        recurringCommitments: 150,
        daysLeft: 15,
      );

      expect(amount.availableAfterCommitments, 450);
      expect(amount.dailyAmount, 30);
      expect(amount.recurringCommitments, 150);
    },
  );

  test('never suggests a negative amount when commitments exceed the plan', () {
    final amount = calculateSpendableAmount(
      totalLimit: 100,
      totalSpent: 60,
      recurringCommitments: 80,
      daysLeft: 10,
    );

    expect(amount.availableAfterCommitments, -40);
    expect(amount.dailyAmount, 0);
  });
}

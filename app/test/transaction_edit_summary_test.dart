import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/transaction_edit_summary.dart';
import 'package:moneylock/data/transaction_summary.dart';

void main() {
  test('round-trips through JSON encode/decode, including a null newMerchant', () {
    final original = TransactionEditSummary(
      transaction: TransactionSummary(
        id: 1,
        merchant: 'Store',
        amount: 45.0,
        category: 'Other',
        timestamp: DateTime(2026, 8, 1),
      ),
      newAmount: 50.0,
      newMerchant: null,
    );

    final decoded = decodeTransactionEditSummary(encodeTransactionEditSummary(original));

    expect(decoded.transaction.merchant, 'Store');
    expect(decoded.newAmount, 50.0);
    expect(decoded.newMerchant, isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/data/transaction_summary.dart';

void main() {
  test('toJson/fromJson round-trips exactly', () {
    final original = TransactionSummary(
      id: 7,
      merchant: 'Nike',
      amount: 89.99,
      category: 'Shopping & E-commerce',
      timestamp: DateTime(2026, 6, 12, 10, 30),
    );

    final decoded = TransactionSummary.fromJson(original.toJson());

    expect(decoded.id, 7);
    expect(decoded.merchant, 'Nike');
    expect(decoded.amount, 89.99);
    expect(decoded.category, 'Shopping & E-commerce');
    expect(decoded.timestamp, DateTime(2026, 6, 12, 10, 30));
  });

  test('decodeTransactionSummaries decodes a JSON-encoded list', () {
    final list = [
      TransactionSummary(
        id: 1,
        merchant: 'A',
        amount: 1.0,
        category: 'Other',
        timestamp: DateTime(2026, 1, 1),
      ),
      TransactionSummary(
        id: 2,
        merchant: 'B',
        amount: 2.0,
        category: 'Other',
        timestamp: DateTime(2026, 1, 2),
      ),
    ];
    final json = encodeTransactionSummaries(list);

    final decoded = decodeTransactionSummaries(json);

    expect(decoded, hasLength(2));
    expect(decoded[0].merchant, 'A');
    expect(decoded[1].merchant, 'B');
  });
}

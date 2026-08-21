import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/dashboard/dashboard_screen.dart' show recentWithinLastWeek;
import 'package:moneylock/data/db.dart';

void main() {
  test('keeps entries within the last 7 days and drops older ones', () {
    final now = DateTime(2026, 8, 19, 12, 0);
    final recent = _tx(id: 1, timestamp: now.subtract(const Duration(days: 2)));
    final boundary = _tx(id: 2, timestamp: now.subtract(const Duration(days: 7)));
    final old = _tx(id: 3, timestamp: now.subtract(const Duration(days: 8)));

    final result = recentWithinLastWeek([recent, boundary, old], now: now);

    expect(result.map((t) => t.id), containsAll([1, 2]));
    expect(result.map((t) => t.id), isNot(contains(3)));
  });

  test('empty input returns empty output', () {
    expect(recentWithinLastWeek(const [], now: DateTime(2026, 8, 19)), isEmpty);
  });
}

Transaction _tx({required int id, required DateTime timestamp}) => Transaction(
      id: id,
      amount: 1.0,
      currency: 'USD',
      merchant: 'Test',
      category: 'Other',
      source: 'manual',
      rawText: 'Test',
      timestamp: timestamp,
      dedupHash: 'hash-$id',
    );

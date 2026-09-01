import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/core/format.dart';

void main() {
  test(
    'formats the configured currency rather than always using US dollars',
    () {
      expect(fmtCurrency(12.5, currency: 'USD'), r'$12.50');
      expect(fmtCurrency(12.5, currency: 'CAD'), r'CA$12.50');
      expect(fmtCurrency(12.5, currency: 'EUR'), '12,50 €');
    },
  );
}

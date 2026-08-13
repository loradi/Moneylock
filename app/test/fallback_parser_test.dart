import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/llm/fallback_parser.dart';

void main() {
  group('fallback parser', () {
    test('extrae monto y merchant de notificacion tipica', () {
      final p = parseFallback('Starbucks \$12.50');
      expect(p!.amount, closeTo(12.50, 0.001));
      expect(p.merchant, 'Starbucks');
      expect(p.category, 'Coffee & Dining');
    });
    test('extrae monto con sufijo USD', () {
      final p = parseFallback('Apple.com 9.99 USD');
      expect(p!.amount, closeTo(9.99, 0.001));
      expect(p.currency, 'USD');
      expect(p.category, 'Shopping & E-commerce');
    });
    test('merchant desconocido -> Other, confianza baja', () {
      final p = parseFallback('FOOBARBAZ \$3.00');
      expect(p!.category, 'Other');
      expect(p.confidence, lessThan(0.5));
    });
    test('sin monto -> null', () {
      expect(parseFallback('hello world'), isNull);
    });
    test('espacios multiples no rompen', () {
      final p = parseFallback('Uber  Trip  20.00  ');
      expect(p!.amount, closeTo(20.00, 0.001));
    });
  });
}
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
    test('receipt total wins over store and item numbers', () {
      final p = parseFallback(
        'Store #842\nItem 12.99\nTax 1.04\nTOTAL 32.00\nThank you',
      );
      expect(p!.amount, 32);
    });
    test('merchant desconocido -> Other, confianza baja', () {
      final p = parseFallback('FOOBARBAZ \$3.00');
      expect(p!.category, 'Other');
      expect(p.confidence, lessThan(0.5));
    });
    test('recognizes an explicit category in a manual Vector entry', () {
      final p = parseFallback('add 54 to groceries');
      expect(p!.amount, 54);
      expect(p.category, 'Groceries');
      expect(p.merchant, isNull);
    });
    test(
      'interpreta un comando de Vector en español sin inventar comercio',
      () {
        final p = parseFallback('agrega 54 al supermercado');
        expect(p!.amount, 54);
        expect(p.category, 'Groceries');
        expect(p.merchant, isNull);
      },
    );
    test('conserva el comercio escrito en un comando de Vector en español', () {
      final p = parseFallback('registra 18.50 en Metro');
      expect(p!.amount, 18.50);
      expect(p.category, 'Other');
      expect(p.merchant, 'Metro');
    });
    test('removes command words from flexible add phrases', () {
      final categoryEntry = parseFallback('add new entry for 120 groceries');
      expect(categoryEntry!.category, 'Groceries');
      expect(categoryEntry.merchant, isNull);

      final merchantEntry = parseFallback('add a purchase 34 on rice');
      expect(merchantEntry!.category, 'Other');
      expect(merchantEntry.merchant, 'Rice');
    });
    test('recognizes a compact merchant and amount entry', () {
      expect(isCompactTransactionEntry('meatloaf 23'), isTrue);
      expect(isCompactTransactionEntry('Tim Hortons 10'), isTrue);
      expect(isCompactTransactionEntry('I have 5 dollars'), isFalse);
      expect(isCompactTransactionEntry('meet me at 5'), isFalse);
      expect(isCompactTransactionEntry('add Netflix for \$30'), isFalse);
    });
    test('does not treat recurring subscriptions as one-off transactions', () {
      expect(
        isExplicitTransactionCommand(
          'add Netflix for \$30 recurring on the 20th',
        ),
        isFalse,
      );
      expect(isExplicitTransactionCommand('add Netflix for \$30'), isFalse);
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

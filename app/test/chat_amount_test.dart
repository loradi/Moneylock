import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/chat/chat_screen.dart';

void main() {
  test('frases habladas sin monto no activan el flujo de transaccion', () {
    expect(hasMonetaryAmount('meet me at 5'), isFalse);
    expect(hasMonetaryAmount('I have 5 dollars'), isFalse);
    expect(hasMonetaryAmount('the 4th of july'), isFalse);
  });

  test('monto con simbolo de dolar o dos decimales activa el flujo', () {
    expect(hasMonetaryAmount('Starbucks 12.50'), isTrue);
    expect(hasMonetaryAmount(r'I spent $20 on lunch'), isTrue);
    expect(hasMonetaryAmount(r'groceries $ 5.5'), isTrue);
    expect(hasMonetaryAmount('ride was 8.00'), isTrue);
  });
}
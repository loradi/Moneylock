import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/features/add/add_transaction_flow.dart';

void main() {
  test('parsea URL del shortcut', () {
    final u = Uri.parse('moneylock://add?amount=45.50&merchant=Starbucks');
    expect(parseShortcutUrl(u), 'Starbucks 45.50 USD');
  });
  test('sin amount lanza FormatException', () {
    expect(() => parseShortcutUrl(Uri.parse('moneylock://add?merchant=X')),
        throwsFormatException);
  });
}
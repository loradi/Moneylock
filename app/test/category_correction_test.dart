import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/llm/category_correction.dart';

void main() {
  test(
    'detecta una petición explícita para cambiar a una categoría válida',
    () {
      expect(parseCategoryCorrection('Change it to Groceries'), 'Groceries');
      expect(
        parseCategoryCorrection('cámbialo a Coffee & Dining'),
        'Coffee & Dining',
      );
    },
  );

  test('no transforma una pregunta financiera normal en corrección', () {
    expect(
      parseCategoryCorrection('How much did I spend on groceries?'),
      isNull,
    );
    expect(
      parseCategoryCorrection('Write code to categorize meatloaf'),
      isNull,
    );
  });
}

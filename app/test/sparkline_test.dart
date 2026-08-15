import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/widgets/sparkline.dart';

void main() {
  test('menos de 2 puntos devuelve null', () {
    expect(normalizeSpark([]), isNull);
    expect(normalizeSpark([3]), isNull);
  });

  test('normaliza a 0..1 manteniendo el maximo en 1', () {
    final normalized = normalizeSpark([0, 5, 10])!;
    expect(normalized, [0.0, 0.5, 1.0]);
  });

  test('serie plana no divide por cero', () {
    final normalized = normalizeSpark([0, 0, 0])!;
    expect(normalized.every((value) => value == 0.0), isTrue);
  });
}

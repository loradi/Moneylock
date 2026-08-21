import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/llm/mentor_agent.dart';

void main() {
  group('assessSpend', () {
    test('bajo el 80% -> info', () {
      expect(assessSpend(350, 500), Severity.info);
    });
    test('en el 80% -> warning', () {
      expect(assessSpend(400, 500), Severity.warning);
    });
    test('sobre el limite -> alert', () {
      expect(assessSpend(500, 500), Severity.alert);
      expect(assessSpend(600, 500), Severity.alert);
    });
    test('sin presupuesto -> info', () {
      expect(assessSpend(100, null), Severity.info);
    });
  });
  group('mentorPromptFor', () {
    test('tono por defecto es strict', () {
      expect(mentorPromptFor('unknown_tone'), contains('strict'));
    });
    test('neutral no contiene estricto', () {
      expect(mentorPromptFor('neutral_analyst'), isNot(contains('estricto')));
    });
  });
}
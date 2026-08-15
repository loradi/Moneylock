import 'package:flutter_test/flutter_test.dart';
import 'package:moneylock/llm/mentor_guardrails.dart';

void main() {
  test('permite preguntas de presupuesto y gasto', () {
    expect(
      mentorRequestAllowed('How much did I spend on coffee this month?'),
      isTrue,
    );
    expect(mentorRequestAllowed('Should I lower my dining budget?'), isTrue);
  });

  test('rechaza solicitudes fuera del alcance financiero', () {
    expect(mentorRequestAllowed('Write me a Python script'), isFalse);
    expect(mentorRequestAllowed('Who should I vote for?'), isFalse);
    expect(mentorRequestAllowed('Help me write a poem'), isFalse);
  });

  test('rechaza asesoría regulada de inversión, impuestos y legal', () {
    expect(mentorRequestAllowed('Which stock should I buy?'), isFalse);
    expect(mentorRequestAllowed('How do I evade taxes?'), isFalse);
    expect(mentorRequestAllowed('Give me legal advice about debt'), isFalse);
  });

  test('reemplaza respuestas con código por una respuesta de alcance', () {
    expect(
      guardMentorResponse('```dart\nprint("hello");\n```'),
      mentorScopeRefusal,
    );
    expect(guardMentorResponse(''), mentorScopeRefusal);
    expect(
      guardMentorResponse('You spent 40% of your dining budget.'),
      contains('40%'),
    );
  });
}

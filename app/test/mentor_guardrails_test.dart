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

  test(
    'permite comandos explícitos de registro aunque el comercio sea nuevo',
    () {
      expect(mentorRequestAllowed('agrega 54 al supermercado'), isTrue);
      expect(mentorRequestAllowed('registra 18.50 en Metro'), isTrue);
    },
  );

  test('permite operaciones de registros y entradas compactas de Vector', () {
    expect(mentorRequestAllowed('meatloaf 23'), isTrue);
    expect(mentorRequestAllowed('show me the last 5 purchases'), isTrue);
    expect(mentorRequestAllowed('can you delete the entry for tren'), isTrue);
  });

  test('rechaza solicitudes fuera del alcance financiero', () {
    expect(mentorRequestAllowed('Write me a Python script'), isFalse);
    expect(mentorRequestAllowed('Who should I vote for?'), isFalse);
    expect(mentorRequestAllowed('Help me write a poem'), isFalse);
  });

  test(
    'permite educación financiera pero mantiene la advertencia en el prompt',
    () {
      expect(mentorRequestAllowed('What is an index fund?'), isTrue);
      expect(mentorRequestAllowed('How does credit utilization work?'), isTrue);
      expect(mentorRequestAllowed('How do taxes affect my savings?'), isTrue);
    },
  );

  test(
    'rechaza investigación o ayuda que no es financiera ni de Moneylock',
    () {
      expect(mentorRequestAllowed('Research the history of Rome'), isFalse);
      expect(
        mentorRequestAllowed('Investigate the best laptop for me'),
        isFalse,
      );
      expect(mentorRequestAllowed('Help me plan a vacation'), isFalse);
    },
  );

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
